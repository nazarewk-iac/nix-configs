// Package llm speaks the OpenAI-compatible chat API of the local fleet, and asks the placement
// manager whether a model may load.
//
// It has no third-party dependency: net/http and encoding/json are enough.
package llm

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

// Defaults of the design.
const (
	// DefaultTimeout is one model call.
	DefaultTimeout = 300 * time.Second
	// DefaultMaxTokens bounds one reply. An extraction array of five items fits well under it.
	DefaultMaxTokens = 2048
	// DefaultTemperature is the deterministic setting.
	DefaultTemperature = 0
)

// Client is one model endpoint.
type Client struct {
	Endpoint    string
	Model       string
	APIKey      string
	HTTP        *http.Client
	MaxTokens   int
	Temperature float64
	// DisableThinking sends chat_template_kwargs {"enable_thinking": false}. The frontier is a
	// reasoning model: without this, `content` is empty and the text lands in `reasoning_content`.
	DisableThinking bool
}

// New returns a client with the design defaults.
func New(endpoint, model, apiKey string, timeout time.Duration) *Client {
	if timeout <= 0 {
		timeout = DefaultTimeout
	}
	return &Client{
		Endpoint:        strings.TrimRight(endpoint, "/"),
		Model:           model,
		APIKey:          strings.TrimSpace(apiKey),
		HTTP:            &http.Client{Timeout: timeout},
		MaxTokens:       DefaultMaxTokens,
		Temperature:     DefaultTemperature,
		DisableThinking: true,
	}
}

// ReadKey reads a bearer key: the first line of the file, trimmed.
//
// The file holds one line and may end without a newline. A missing or empty file is an error
// that names the flag, so an operator can fix the call.
func ReadKey(path string) (string, error) {
	if strings.TrimSpace(path) == "" {
		return "", nil
	}
	body, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("cannot read the model API key file %s: %w; pass --key-file", path, err)
	}
	line, _, _ := strings.Cut(string(body), "\n")
	line = strings.TrimSpace(line)
	if line == "" {
		return "", fmt.Errorf("the model API key file %s is empty; pass --key-file", path)
	}
	return line, nil
}

// Result is one completed response.
type Result struct {
	Content          string
	Model            string
	PromptTokens     int
	CompletionTokens int
	Duration         time.Duration
}

// Rate is the generated tokens per second, or 0 when the reply carried no usage.
func (r *Result) Rate() float64 {
	if r.Duration <= 0 || r.CompletionTokens == 0 {
		return 0
	}
	return float64(r.CompletionTokens) / r.Duration.Seconds()
}

// APIError is a non-200 answer of the endpoint.
type APIError struct {
	Status  int
	Message string
	Hint    string
}

func (e *APIError) Error() string {
	if e.Hint == "" {
		return fmt.Sprintf("model endpoint answered %d: %s", e.Status, e.Message)
	}
	return fmt.Sprintf("model endpoint answered %d: %s (%s)", e.Status, e.Message, e.Hint)
}

type chatRequest struct {
	Model              string         `json:"model"`
	Messages           []chatMessage  `json:"messages"`
	Temperature        float64        `json:"temperature"`
	MaxTokens          int            `json:"max_tokens,omitempty"`
	Stream             bool           `json:"stream"`
	ChatTemplateKwargs map[string]any `json:"chat_template_kwargs,omitempty"`
}

type chatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type chatResponse struct {
	Model   string `json:"model"`
	Choices []struct {
		Message struct {
			Content          string `json:"content"`
			ReasoningContent string `json:"reasoning_content"`
		} `json:"message"`
	} `json:"choices"`
	Usage struct {
		PromptTokens     int `json:"prompt_tokens"`
		CompletionTokens int `json:"completion_tokens"`
	} `json:"usage"`
	Error json.RawMessage `json:"error"`
}

// Chat sends one system and user message and returns the reply text.
func (c *Client) Chat(ctx context.Context, system, user string) (*Result, error) {
	request := chatRequest{
		Model: c.Model,
		Messages: []chatMessage{
			{Role: "system", Content: system},
			{Role: "user", Content: user},
		},
		Temperature: c.Temperature,
		MaxTokens:   c.MaxTokens,
	}
	if c.DisableThinking {
		request.ChatTemplateKwargs = map[string]any{"enable_thinking": false}
	}
	body, err := json.Marshal(request)
	if err != nil {
		return nil, err
	}
	url := c.Endpoint + "/chat/completions"
	started := time.Now()
	httpRequest, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	httpRequest.Header.Set("Content-Type", "application/json")
	httpRequest.Header.Set("Accept", "application/json")
	if c.APIKey != "" {
		httpRequest.Header.Set("Authorization", "Bearer "+c.APIKey)
	}
	response, err := c.HTTP.Do(httpRequest)
	if err != nil {
		return nil, err
	}
	defer func() {
		_ = response.Body.Close()
	}()
	raw, err := io.ReadAll(io.LimitReader(response.Body, 32<<20))
	if err != nil {
		return nil, err
	}
	elapsed := time.Since(started)

	if response.StatusCode != http.StatusOK {
		message := errorMessage(raw)
		return nil, &APIError{Status: response.StatusCode, Message: message, Hint: hintFor(response.StatusCode, message)}
	}
	var parsed chatResponse
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return nil, fmt.Errorf("model endpoint returned invalid JSON: %w", err)
	}
	if len(parsed.Error) > 0 && string(parsed.Error) != "null" {
		message := errorMessage(raw)
		return nil, &APIError{Status: response.StatusCode, Message: message, Hint: hintFor(response.StatusCode, message)}
	}
	if len(parsed.Choices) == 0 {
		return nil, errors.New("model endpoint returned no choices")
	}
	content := parsed.Choices[0].Message.Content
	if strings.TrimSpace(content) == "" && strings.TrimSpace(parsed.Choices[0].Message.ReasoningContent) != "" {
		return nil, errors.New(
			"the reply has only reasoning_content: this model needs chat_template_kwargs " +
				`{"enable_thinking": false}, which this client sends by default`)
	}
	model := parsed.Model
	if model == "" {
		model = c.Model
	}
	return &Result{
		Content:          content,
		Model:            model,
		PromptTokens:     parsed.Usage.PromptTokens,
		CompletionTokens: parsed.Usage.CompletionTokens,
		Duration:         elapsed,
	}, nil
}

// errorMessage accepts both {"error":{"message":...}} and {"error":"..."}.
func errorMessage(raw []byte) string {
	var probe struct {
		Error json.RawMessage `json:"error"`
	}
	if err := json.Unmarshal(raw, &probe); err != nil || len(probe.Error) == 0 {
		return strings.TrimSpace(string(raw))
	}
	var object struct {
		Message string `json:"message"`
		Code    string `json:"code"`
	}
	if err := json.Unmarshal(probe.Error, &object); err == nil {
		if object.Message != "" {
			if object.Code != "" {
				return object.Message + " [" + object.Code + "]"
			}
			return object.Message
		}
	}
	var text string
	if err := json.Unmarshal(probe.Error, &text); err == nil {
		return text
	}
	return strings.TrimSpace(string(probe.Error))
}

// hintFor turns the failure modes of this fleet into an actionable sentence.
func hintFor(status int, message string) string {
	lower := strings.ToLower(message)
	switch {
	case status == http.StatusUnauthorized || strings.Contains(lower, "invalid api key"):
		return "the endpoint wants a bearer key; pass --key-file with a one-line key file"
	case strings.Contains(lower, "no router for requested model"):
		return "this id is a purpose alias with no router; pass a base model id from /v1/models, " +
			"for example qfn"
	case strings.Contains(lower, "upstream command exited prematurely"):
		return "the engine could not start; the placement manager refused the model beside the " +
			"resting profile. Use qfn, or switch to a colo profile on purpose"
	case strings.Contains(lower, "context") || strings.Contains(lower, "exceeds"):
		return "the prompt is larger than the model window; pass --chunk-chars 24000"
	case strings.Contains(lower, "connection refused"):
		return "nothing listens on that address; check --endpoint and that llama-swap runs"
	}
	return ""
}
