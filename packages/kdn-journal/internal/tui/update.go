package tui

import (
	"fmt"
	"os/exec"
	"path/filepath"

	tea "github.com/charmbracelet/bubbletea"
)

// editorFinishedMsg is delivered when the `$EDITOR` hand-off returns.
type editorFinishedMsg struct{ err error }

// Update handles one message.
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		if m.width <= 0 {
			m.width = defaultWidth
		}
		if m.height <= 0 {
			m.height = defaultHeight
		}
		m.clampCursor(false)
		m.ensureCursorVisible()
		return m, nil
	case editorFinishedMsg:
		return m.refresh(msg.err), nil
	case tea.KeyMsg:
		return m.handleKey(msg)
	}
	return m, nil
}

func (m Model) handleKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	key := msg.String()
	if m.filterMode {
		return m.handleFilterKey(msg, key)
	}
	switch key {
	case "q", "ctrl+c":
		return m, tea.Quit
	case "tab":
		return m.switchTab(), nil
	case "shift+tab":
		return m.switchTab(), nil
	case "j", "down":
		return m.moveCursor(1), nil
	case "k", "up":
		return m.moveCursor(-1), nil
	case "g":
		if m.fullDetail {
			return m.scrollDetail(-1 << 20), nil
		}
		return m.jumpCursor(0), nil
	case "G":
		if m.fullDetail {
			return m.scrollDetail(1 << 20), nil
		}
		return m.jumpCursor(m.listLen() - 1), nil
	case "enter":
		if m.listLen() == 0 {
			m.status = "nothing to open"
			return m, nil
		}
		m.fullDetail = true
		m.detailScroll = 0
		m.status = ""
		return m, nil
	case "esc":
		switch {
		case m.fullDetail:
			m.fullDetail = false
			m.detailScroll = 0
			m.status = ""
		case m.filter != "":
			m.filter = ""
			m.refilter()
			m.status = "filter cleared"
		}
		return m, nil
	case "/":
		m.filterMode = true
		m.filterBefore = m.filter
		m.status = ""
		return m, nil
	case "e":
		return m.edit()
	case "r":
		return m.refresh(nil), nil
	case "pgdown", "ctrl+f":
		return m.scrollDetail(m.bodyHeight()), nil
	case "pgup", "ctrl+b":
		return m.scrollDetail(-m.bodyHeight()), nil
	case "ctrl+d":
		return m.scrollDetail(m.bodyHeight() / 2), nil
	case "ctrl+u":
		return m.scrollDetail(-m.bodyHeight() / 2), nil
	}
	return m, nil
}

// handleFilterKey routes a key while the filter prompt is open. Only enter and esc leave the mode,
// so `q`, `j`, `k` and `tab` are typed into the query instead of acting on the model.
func (m Model) handleFilterKey(msg tea.KeyMsg, key string) (tea.Model, tea.Cmd) {
	switch key {
	case "enter":
		m.filterMode = false
		m.filterBefore = ""
		m.refilter()
		m.clampCursor(true)
		if m.filter == "" {
			m.status = "filter cleared"
		} else {
			m.status = fmt.Sprintf("filter %q: %d of %d", m.filter, m.listLen(), len(m.allTasks)+len(m.allSessions))
		}
		return m, nil
	case "esc":
		m.filterMode = false
		m.filter = m.filterBefore
		m.filterBefore = ""
		m.refilter()
		m.status = "filter cancelled"
		return m, nil
	case "ctrl+c":
		return m, tea.Quit
	case "backspace":
		if runes := []rune(m.filter); len(runes) > 0 {
			m.filter = string(runes[:len(runes)-1])
		}
		return m, nil
	case "ctrl+u":
		m.filter = ""
		return m, nil
	}
	if text, ok := typedText(msg); ok {
		m.filter += text
	}
	return m, nil
}

// typedText extracts the printable text of a key message.
func typedText(msg tea.KeyMsg) (string, bool) {
	if msg.Type == tea.KeySpace {
		return " ", true
	}
	if msg.Type != tea.KeyRunes || len(msg.Runes) == 0 {
		return "", false
	}
	return string(msg.Runes), true
}

func (m Model) switchTab() Model {
	if m.tab == TabTasks {
		m.tab = TabSessions
	} else {
		m.tab = TabTasks
	}
	m.fullDetail = false
	m.clampCursor(true)
	m.ensureCursorVisible()
	m.status = ""
	return m
}

func (m Model) moveCursor(delta int) Model {
	m.cursor += delta
	m.clampCursor(false)
	m.detailScroll = 0
	m.ensureCursorVisible()
	return m
}

func (m Model) jumpCursor(index int) Model {
	if index < 0 {
		index = 0
	}
	m.cursor = index
	m.clampCursor(false)
	m.detailScroll = 0
	m.ensureCursorVisible()
	return m
}

func (m Model) scrollDetail(delta int) Model {
	height := m.bodyHeight()
	content := len(m.detailForPane(m.paneWidth()))
	limit := content - height
	if limit < 0 {
		limit = 0
	}
	m.detailScroll += delta
	if m.detailScroll < 0 {
		m.detailScroll = 0
	}
	if m.detailScroll > limit {
		m.detailScroll = limit
	}
	return m
}

// ensureCursorVisible scrolls the list so the cursor row is inside the pane.
func (m *Model) ensureCursorVisible() {
	height := m.bodyHeight()
	if height < 1 {
		height = 1
	}
	if m.cursor < m.listOffset {
		m.listOffset = m.cursor
	}
	if m.cursor >= m.listOffset+height {
		m.listOffset = m.cursor - height + 1
	}
	if m.listOffset < 0 {
		m.listOffset = 0
	}
}

// edit hands the selected primary file to `$EDITOR`. It is a no-op with a status message when the
// file is absent, so the TUI never writes a journal itself.
func (m Model) edit() (tea.Model, tea.Cmd) {
	path := m.primaryPath()
	if path == "" {
		m.status = "no editable file for this selection"
		return m, nil
	}
	editor := m.editor()
	// #nosec G204 -- the editor is chosen by the user through Deps/$EDITOR. Run it through a
	// shell so a value such as `code -w` or `nvim -u NONE` keeps its arguments.
	command := exec.Command("sh", "-c", editor+" \"$1\"", "sh", path)
	m.status = "editing " + filepath.Base(path)
	return m, tea.ExecProcess(command, func(err error) tea.Msg {
		return editorFinishedMsg{err: err}
	})
}

// refresh reloads the tree and the store from disk and reports the result.
func (m Model) refresh(editorErr error) Model {
	if m.deps.Reload == nil {
		m.status = "reload is unavailable"
		return m
	}
	tree, store, err := m.deps.Reload()
	if err != nil {
		m.status = "reload failed: " + err.Error()
		return m
	}
	m.setTree(tree)
	m.setStore(store)
	m.refilter()
	m.clampCursor(true)
	m.ensureCursorVisible()
	status := fmt.Sprintf("reloaded: %d tasks, %d sessions", len(m.allTasks), len(m.allSessions))
	if editorErr != nil {
		status = "editor: " + editorErr.Error() + " · " + status
	}
	m.status = status
	return m
}
