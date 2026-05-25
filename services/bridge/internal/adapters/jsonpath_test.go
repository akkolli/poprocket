package adapters

import "testing"

func TestSelectJSONPath(t *testing.T) {
	value := map[string]any{
		"heartbeatList": map[string]any{
			"nas": []any{
				map[string]any{"status": float64(1)},
			},
		},
	}
	got, ok := SelectJSONPath(value, "$.heartbeatList.nas[0].status")
	if !ok {
		t.Fatal("SelectJSONPath ok = false")
	}
	if got != float64(1) {
		t.Fatalf("got = %#v", got)
	}
}
