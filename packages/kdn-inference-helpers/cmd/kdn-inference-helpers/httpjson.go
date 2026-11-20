package main

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"time"
)

// jsonBody encodes a request body; a nil body becomes an empty object, which every endpoint accepts.
func jsonBody(body any) (io.Reader, error) {
	if body == nil {
		return strings.NewReader("{}"), nil
	}
	raw, err := json.Marshal(body)
	if err != nil {
		return nil, err
	}
	return bytes.NewReader(raw), nil
}

// decode reads a JSON response.
func decode(r io.Reader, out any) error {
	return json.NewDecoder(r).Decode(out)
}

// postJSON sends a POST and decodes the reply. A non-2xx response is an error that carries the body,
// because a control plane that answers 400 with a reason is more useful than one that just fails.
func postJSON(ctx context.Context, url string, body, out any) error {
	payload, err := jsonBody(body)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, payload)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		detail, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return errStatus(resp.StatusCode, string(detail))
	}
	if out == nil {
		return nil
	}
	return decode(resp.Body, out)
}

// getJSON fetches and decodes a GET reply.
func getJSON(ctx context.Context, url string, out any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		detail, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return errStatus(resp.StatusCode, string(detail))
	}
	return decode(resp.Body, out)
}

type httpStatusError struct {
	code   int
	detail string
}

func (e httpStatusError) Error() string {
	return strings.TrimSpace(strings.Join([]string{http.StatusText(e.code), e.detail}, ": "))
}

func errStatus(code int, detail string) error { return httpStatusError{code: code, detail: detail} }
