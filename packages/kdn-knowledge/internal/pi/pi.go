// Package pi reads the session files of the Pi harness.
//
// A Pi session is one JSONL file. The first line is a session header with the id, the timestamp
// and the working directory; the following lines are events, of which `message` events carry the
// transcript. The project comes from the header `cwd`, never from the directory slug.
package pi

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"kdn-knowledge/internal/corpus"
)

// Source is the corpus source name of this harness.
const Source = "pi"

// maxLine is the largest JSONL line that the scanner accepts.
const maxLine = 64 << 20

// Meta is what the selection needs, without the transcript.
type Meta struct {
	Path    string
	ID      string
	Cwd     string
	Started time.Time
	Updated time.Time
	Title   string
}

// Walk returns every session file under root, sorted by path.
func Walk(root string) ([]string, error) {
	info, err := os.Stat(root)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("%s is not a directory", root)
	}
	paths := make([]string, 0, 256)
	err = filepath.WalkDir(root, func(path string, entry os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() {
			return nil
		}
		if strings.HasSuffix(entry.Name(), ".jsonl") {
			paths = append(paths, path)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Strings(paths)
	return paths, nil
}

// Index reads the header and the first user text of one file. It stops early, so walking a
// directory costs little.
func Index(path string) (Meta, error) {
	meta := Meta{Path: path}
	info, err := os.Stat(path)
	if err != nil {
		return meta, err
	}
	meta.Updated = info.ModTime().UTC()
	foundHeader := false
	err = scan(path, func(line []byte) bool {
		var event struct {
			Type      string `json:"type"`
			ID        string `json:"id"`
			Timestamp string `json:"timestamp"`
			Cwd       string `json:"cwd"`
			Message   *struct {
				Role    string          `json:"role"`
				Content json.RawMessage `json:"content"`
			} `json:"message"`
		}
		if json.Unmarshal(line, &event) != nil {
			return true
		}
		switch event.Type {
		case "session":
			foundHeader = true
			meta.ID = event.ID
			meta.Cwd = event.Cwd
			meta.Started = parseTime(event.Timestamp)
		case "message":
			if event.Message == nil || event.Message.Role != "user" {
				return true
			}
			if text := userText(event.Message.Content); text != "" {
				meta.Title = titleOf(text)
				return false
			}
		}
		return true
	})
	if err != nil {
		return meta, err
	}
	if !foundHeader || meta.ID == "" {
		return meta, fmt.Errorf("%s has no session header", path)
	}
	if meta.Title == "" {
		meta.Title = "Pi session " + shortID(meta.ID)
	}
	return meta, nil
}

// Load reads one whole session. It returns the session and the number of malformed lines that it
// skipped; a malformed line never fails the file.
func Load(path string, toolChars int) (corpus.Session, int, error) {
	if toolChars <= 0 {
		toolChars = corpus.ToolChars
	}
	var session corpus.Session
	malformed := 0
	pending := make([]string, 0, 8)
	hasDialogue := false

	flush := func() {
		text := strings.TrimSpace(strings.Join(pending, "\n"))
		pending = pending[:0]
		if text == "" {
			return
		}
		session.Messages = append(session.Messages, corpus.Message{Role: "assistant", Text: text})
		hasDialogue = true
	}

	err := scan(path, func(line []byte) bool {
		var event struct {
			Type      string `json:"type"`
			ID        string `json:"id"`
			Timestamp string `json:"timestamp"`
			Cwd       string `json:"cwd"`
			Message   *struct {
				Role      string          `json:"role"`
				Content   json.RawMessage `json:"content"`
				ToolName  string          `json:"toolName"`
				Arguments json.RawMessage `json:"arguments"`
			} `json:"message"`
		}
		if err := json.Unmarshal(line, &event); err != nil {
			malformed++
			return true
		}
		switch event.Type {
		case "session":
			session.ID = event.ID
			session.Directory = event.Cwd
			session.Started = parseTime(event.Timestamp)
		case "message":
			if event.Message == nil {
				return true
			}
			switch event.Message.Role {
			case "system":
				// The harness prompt is not knowledge.
			case "user":
				flush()
				text := userText(event.Message.Content)
				if text == "" {
					return true
				}
				session.Messages = append(session.Messages, corpus.Message{Role: "user", Text: text})
				hasDialogue = true
			case "assistant":
				for _, part := range partsOf(event.Message.Content) {
					switch part.Type {
					case "thinking":
						// Dropped on purpose.
					case "text":
						if strings.TrimSpace(part.Text) != "" {
							pending = append(pending, strings.TrimSpace(part.Text))
						}
					case "toolCall":
						flush()
						message := corpus.Message{
							Role:    "tool",
							Name:    strings.TrimSpace(part.Name),
							Command: commandOf(part.Arguments),
							Text:    truncate(compact(part.Arguments), toolChars),
						}
						if message.Text == "" {
							message.Text = message.Name
						}
						if message.Text != "" {
							session.Messages = append(session.Messages, message)
						}
					}
				}
			case "toolResult":
				flush()
				text := partsText(event.Message.Content)
				if text == "" {
					return true
				}
				session.Messages = append(session.Messages, corpus.Message{
					Role: "tool",
					Name: strings.TrimSpace(event.Message.ToolName),
					Text: truncate(text, toolChars),
				})
			}
		}
		return true
	})
	if err != nil {
		return session, malformed, err
	}
	flush()
	if session.ID == "" {
		return session, malformed, fmt.Errorf("%s has no session header", path)
	}
	if !hasDialogue {
		// A session with no user or assistant text carries nothing to extract.
		return corpus.Session{}, malformed, nil
	}
	session.Source = Source
	if session.Started.IsZero() {
		if info, err := os.Stat(path); err == nil {
			session.Started = info.ModTime().UTC()
		}
	}
	if session.Title == "" {
		session.Title = firstUserText(session)
	}
	session.Hash = corpus.Hash(session.Messages)
	return session, malformed, nil
}

// IDs returns the session ids under root, reading only the header of each file.
func IDs(root string) (map[string]struct{}, error) {
	paths, err := Walk(root)
	if err != nil {
		return nil, err
	}
	ids := make(map[string]struct{}, len(paths))
	for _, path := range paths {
		meta, err := Index(path)
		if err != nil {
			continue
		}
		ids[meta.ID] = struct{}{}
	}
	return ids, nil
}

type part struct {
	Type      string          `json:"type"`
	Text      string          `json:"text"`
	Name      string          `json:"name"`
	Arguments json.RawMessage `json:"arguments"`
}

func partsOf(raw json.RawMessage) []part {
	if len(raw) == 0 {
		return nil
	}
	var list []part
	if err := json.Unmarshal(raw, &list); err == nil {
		return list
	}
	return nil
}

func partsText(raw json.RawMessage) string {
	var builder strings.Builder
	for _, item := range partsOf(raw) {
		if item.Type != "text" || strings.TrimSpace(item.Text) == "" {
			continue
		}
		if builder.Len() > 0 {
			builder.WriteString("\n")
		}
		builder.WriteString(strings.TrimSpace(item.Text))
	}
	return builder.String()
}

func userText(raw json.RawMessage) string {
	if len(raw) == 0 {
		return ""
	}
	var text string
	if err := json.Unmarshal(raw, &text); err == nil {
		return strings.TrimSpace(text)
	}
	return strings.TrimSpace(partsText(raw))
}

func commandOf(raw json.RawMessage) string {
	if len(raw) == 0 {
		return ""
	}
	var parsed map[string]any
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return ""
	}
	switch value := parsed["command"].(type) {
	case string:
		return strings.TrimSpace(value)
	case []any:
		parts := make([]string, 0, len(value))
		for _, item := range value {
			if text, ok := item.(string); ok {
				parts = append(parts, text)
			}
		}
		return strings.TrimSpace(strings.Join(parts, " "))
	}
	return ""
}

func compact(raw json.RawMessage) string {
	if len(raw) == 0 {
		return ""
	}
	var buffer bytes.Buffer
	if err := json.Compact(&buffer, raw); err != nil {
		return strings.TrimSpace(string(raw))
	}
	return buffer.String()
}

func truncate(text string, limit int) string {
	runes := []rune(text)
	if len(runes) <= limit {
		return text
	}
	marker := []rune("\n… [truncated]")
	keep := limit - len(marker)
	if keep < 0 {
		keep = limit
		marker = nil
	}
	return string(runes[:keep]) + string(marker)
}

func parseTime(value string) time.Time {
	value = strings.TrimSpace(value)
	if value == "" {
		return time.Time{}
	}
	for _, layout := range []string{time.RFC3339Nano, time.RFC3339, "2006-01-02T15:04:05.999Z07:00"} {
		if parsed, err := time.Parse(layout, value); err == nil {
			return parsed.UTC()
		}
	}
	return time.Time{}
}

func titleOf(text string) string {
	text = strings.TrimSpace(text)
	if index := strings.IndexAny(text, "\r\n"); index >= 0 {
		text = text[:index]
	}
	text = strings.Join(strings.Fields(text), " ")
	if len(text) > 80 {
		text = string([]rune(text)[:77]) + "…"
	}
	return text
}

func firstUserText(session corpus.Session) string {
	for _, message := range session.Messages {
		if message.Role == "user" && strings.TrimSpace(message.Text) != "" {
			return titleOf(message.Text)
		}
	}
	return "Pi session " + shortID(session.ID)
}

func shortID(id string) string {
	if len(id) > 8 {
		return id[:8]
	}
	return id
}

// scan feeds every line to visit until it returns false.
func scan(path string, visit func(line []byte) bool) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer func() {
		_ = file.Close()
	}()
	reader := bufio.NewReaderSize(file, 256*1024)
	for {
		line, err := readLine(reader)
		if len(line) > 0 {
			trimmed := bytes.TrimSpace(line)
			if len(trimmed) > 0 && !visit(trimmed) {
				return nil
			}
		}
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
	}
}

// readLine reads one line of any length, up to maxLine.
func readLine(reader *bufio.Reader) ([]byte, error) {
	var builder bytes.Buffer
	for {
		chunk, err := reader.ReadSlice('\n')
		if builder.Len()+len(chunk) > maxLine {
			return nil, fmt.Errorf("line is over %d bytes", maxLine)
		}
		builder.Write(chunk)
		if err == bufio.ErrBufferFull {
			continue
		}
		return builder.Bytes(), err
	}
}
