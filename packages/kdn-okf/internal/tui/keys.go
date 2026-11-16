package tui

import "github.com/charmbracelet/bubbles/key"

// keyMap is the shell key map. The list keeps its own bindings; the shell owns the letters it
// freed by rebinding the list's page keys.
type keyMap struct {
	Up        key.Binding
	Down      key.Binding
	Open      key.Binding
	Back      key.Binding
	Filter    key.Binding
	Status    key.Binding
	Trust     key.Binding
	Stale     key.Binding
	Sort      key.Binding
	SortBack  key.Binding
	Clear     key.Binding
	Links     key.Binding
	Backlinks key.Binding
	Preview   key.Binding
	Edit      key.Binding
	Reload    key.Binding
	Quit      key.Binding
}

func defaultKeyMap() keyMap {
	return keyMap{
		Up:        key.NewBinding(key.WithKeys("k", "up"), key.WithHelp("k", "up")),
		Down:      key.NewBinding(key.WithKeys("j", "down"), key.WithHelp("j", "down")),
		Open:      key.NewBinding(key.WithKeys("enter"), key.WithHelp("enter", "detail")),
		Back:      key.NewBinding(key.WithKeys("esc"), key.WithHelp("esc", "back")),
		Filter:    key.NewBinding(key.WithKeys("/"), key.WithHelp("/", "filter")),
		Status:    key.NewBinding(key.WithKeys("f"), key.WithHelp("f", "status")),
		Trust:     key.NewBinding(key.WithKeys("u"), key.WithHelp("u", "trust")),
		Stale:     key.NewBinding(key.WithKeys("x"), key.WithHelp("x", "stale")),
		Sort:      key.NewBinding(key.WithKeys("s"), key.WithHelp("s", "sort")),
		SortBack:  key.NewBinding(key.WithKeys("S"), key.WithHelp("S", "sort back")),
		Clear:     key.NewBinding(key.WithKeys("c"), key.WithHelp("c", "clear")),
		Links:     key.NewBinding(key.WithKeys("l"), key.WithHelp("l", "links")),
		Backlinks: key.NewBinding(key.WithKeys("b"), key.WithHelp("b", "backlinks")),
		Preview:   key.NewBinding(key.WithKeys("v"), key.WithHelp("v", "preview")),
		Edit:      key.NewBinding(key.WithKeys("o"), key.WithHelp("o", "edit")),
		Reload:    key.NewBinding(key.WithKeys("r"), key.WithHelp("r", "reload")),
		Quit:      key.NewBinding(key.WithKeys("q", "ctrl+c"), key.WithHelp("q", "quit")),
	}
}

// ShortHelp implements help.KeyMap.
func (k keyMap) ShortHelp() []key.Binding {
	return []key.Binding{k.Down, k.Open, k.Filter, k.Status, k.Trust, k.Sort, k.Links, k.Backlinks, k.Edit, k.Quit}
}

// FullHelp implements help.KeyMap.
func (k keyMap) FullHelp() [][]key.Binding {
	return [][]key.Binding{
		{k.Up, k.Down, k.Open, k.Back},
		{k.Filter, k.Status, k.Trust, k.Stale},
		{k.Sort, k.SortBack, k.Clear, k.Preview},
		{k.Links, k.Backlinks, k.Edit, k.Reload, k.Quit},
	}
}
