package adapters

import (
	"strconv"
	"strings"
)

func SelectJSONPath(value any, path string) (any, bool) {
	if path == "" || path == "$" {
		return value, true
	}
	path = strings.TrimPrefix(path, "$.")
	current := value
	for _, rawPart := range strings.Split(path, ".") {
		if rawPart == "" {
			return nil, false
		}
		key, index, hasIndex := parsePart(rawPart)
		object, ok := current.(map[string]any)
		if !ok {
			return nil, false
		}
		current, ok = object[key]
		if !ok {
			return nil, false
		}
		if hasIndex {
			array, ok := current.([]any)
			if !ok || index < 0 || index >= len(array) {
				return nil, false
			}
			current = array[index]
		}
	}
	return current, true
}

func parsePart(part string) (string, int, bool) {
	open := strings.IndexByte(part, '[')
	close := strings.IndexByte(part, ']')
	if open == -1 || close == -1 || close <= open {
		return part, 0, false
	}
	index, err := strconv.Atoi(part[open+1 : close])
	if err != nil {
		return part[:open], -1, true
	}
	return part[:open], index, true
}
