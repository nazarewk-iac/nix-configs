package tui

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/charmbracelet/bubbles/list"
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
		m.syncLayout()
		m.syncDetail()
		return m, nil
	case list.FilterMatchesMsg:
		// The active list filtering is asynchronous. Feed the result to both lists; the one that
		// is filtering accepts it and the other ignores it.
		var cmds []tea.Cmd
		var cmd tea.Cmd
		m.tasks, cmd = m.tasks.Update(msg)
		cmds = append(cmds, cmd)
		m.sessions, cmd = m.sessions.Update(msg)
		cmds = append(cmds, cmd)
		m.syncDetail()
		return m, tea.Batch(cmds...)
	case editorFinishedMsg:
		model, cmd := m.refresh(msg.err)
		return model, cmd
	case tea.KeyMsg:
		return m.handleKey(msg)
	}
	return m, nil
}

func (m Model) handleKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	key := msg.String()

	// While the list filter is open, every key belongs to the list. This is what makes `q`, `j`,
	// `k` and `tab` typeable. `ctrl+c` is the escape hatch.
	if m.listModel().FilterState() == list.Filtering {
		if key == "ctrl+c" {
			return m, tea.Quit
		}
		return m, m.updateList(msg)
	}

	switch key {
	case "q", "ctrl+c":
		return m, tea.Quit
	case "tab", "shift+tab":
		m.switchTab()
		return m, nil
	case "1":
		if m.tab != TabTasks {
			m.tab = TabTasks
			m.fullDetail = false
			m.syncLayout()
			m.syncDetail()
		}
		return m, nil
	case "2":
		if m.tab != TabSessions {
			m.tab = TabSessions
			m.fullDetail = false
			m.syncLayout()
			m.syncDetail()
		}
		return m, nil
	case "enter":
		if !m.fullDetail {
			m.toggleDetail()
		}
		return m, nil
	case "esc":
		switch {
		case m.fullDetail:
			m.toggleDetail()
		case m.listModel().FilterState() == list.FilterApplied:
			l := m.activeList()
			l.ResetFilter()
			m.syncDetail()
		}
		return m, nil
	case "e":
		return m.edit()
	case "f":
		return m, m.cycleFacet()
	case "s":
		return m, m.cycleSort()
	case "c":
		return m, m.clearFilters()
	case "r":
		model, cmd := m.refresh(nil)
		return model, cmd
	case "pgup", "ctrl+b", "pgdown", "ctrl+f", "ctrl+u", "ctrl+d":
		// Page keys always scroll the detail pane in split view.
		return m, m.updateDetail(msg)
	case "j", "down", "k", "up", "g", "G", "home", "end":
		if m.fullDetail {
			return m, m.updateDetail(msg)
		}
		return m, m.updateList(msg)
	default:
		if m.fullDetail {
			return m, m.updateDetail(msg)
		}
		return m, m.updateList(msg)
	}
}

// updateList sends a message to the active list and refreshes the detail after the selection or
// filter changes.
func (m *Model) updateList(msg tea.Msg) tea.Cmd {
	l := m.activeList()
	updated, cmd := l.Update(msg)
	*l = updated
	m.syncDetail()
	return cmd
}

func (m *Model) updateDetail(msg tea.Msg) tea.Cmd {
	updated, cmd := m.detail.Update(msg)
	m.detail = updated
	return cmd
}

// edit hands the selected primary file to `$EDITOR`. It is a no-op with a status message when the
// file is absent, so the TUI never writes a journal itself.
func (m Model) edit() (tea.Model, tea.Cmd) {
	path := m.primaryPath()
	if path == "" || !fileExists(path) {
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
func (m *Model) refresh(editorErr error) (Model, tea.Cmd) {
	if m.deps.Reload == nil {
		m.status = "reload is unavailable"
		return *m, nil
	}
	tree, store, err := m.deps.Reload()
	if err != nil {
		m.status = "reload failed: " + err.Error()
		return *m, nil
	}
	treeCmd := m.setTree(tree)
	storeCmd := m.setStore(store)
	m.syncLayout()
	m.syncDetail()
	status := fmt.Sprintf("reloaded: %d items", len(m.tasks.Items())+len(m.sessions.Items()))
	if editorErr != nil {
		status = "editor: " + editorErr.Error() + " · " + status
	}
	m.status = status
	return *m, tea.Batch(treeCmd, storeCmd)
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}
