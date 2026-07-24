package ffi

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	openai "github.com/openai/openai-go/v3"
	"github.com/openai/openai-go/v3/option"
)

func TestParseChatRequest(t *testing.T) {
	request, err := ParseChatRequest([]byte(`{"prompt":"  hello  ","previous_response_id":" resp_123 "}`))
	if err != nil {
		t.Fatal(err)
	}
	if request.Prompt != "hello" || request.PreviousResponseID != "resp_123" {
		t.Fatalf("unexpected request: %#v", request)
	}

	for _, body := range []string{
		`{}`,
		`{"prompt":""}`,
		`{"prompt":"hello","unknown":true}`,
		`{"prompt":"hello"} {"prompt":"again"}`,
	} {
		if _, err := ParseChatRequest([]byte(body)); err == nil {
			t.Fatalf("expected %q to fail", body)
		}
	}
}

func testClient(baseURL string) *Client {
	return &Client{client: openai.NewClient(
		option.WithAPIKey("test"),
		option.WithBaseURL(baseURL+"/"),
	)}
}

func TestChatStreamExposesTextAndResponseID(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if request.URL.Path != "/responses" {
			http.NotFound(writer, request)
			return
		}
		body, err := io.ReadAll(request.Body)
		if err != nil {
			t.Error(err)
			return
		}
		payload := string(body)
		for _, expected := range []string{`"model":"gpt-4o-mini"`, `"input":"hello"`, `"previous_response_id":"resp_previous"`} {
			if !strings.Contains(payload, expected) {
				t.Errorf("request body %s does not contain %s", payload, expected)
			}
		}

		writer.Header().Set("Content-Type", "text/event-stream")
		writer.WriteHeader(http.StatusOK)
		_, _ = io.WriteString(writer, "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Hi\"}\n\n")
		_, _ = io.WriteString(writer, "data: {\"type\":\"response.output_text.delta\",\"delta\":\" there\"}\n\n")
		_, _ = io.WriteString(writer, "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_complete\"}}\n\n")
		_, _ = io.WriteString(writer, "data: [DONE]\n\n")
	}))
	defer server.Close()

	client := testClient(server.URL)
	stream := client.Stream(context.Background(), "hello", "resp_previous")
	defer stream.Close()

	var text strings.Builder
	for stream.Next() {
		text.WriteString(stream.Delta())
	}
	if err := stream.Err(); err != nil {
		t.Fatal(err)
	}
	if text.String() != "Hi there" {
		t.Fatalf("unexpected streamed text: %q", text.String())
	}
	if stream.ResponseID() != "resp_complete" {
		t.Fatalf("unexpected response ID: %q", stream.ResponseID())
	}
}

func TestChatStreamRejectsPrematureEOF(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		writer.Header().Set("Content-Type", "text/event-stream")
		_, _ = io.WriteString(writer, "data: {\"type\":\"response.output_text.delta\",\"delta\":\"partial\"}\n\n")
		_, _ = io.WriteString(writer, "data: [DONE]\n\n")
	}))
	defer server.Close()

	stream := testClient(server.URL).Stream(context.Background(), "hello", "")
	defer stream.Close()
	for stream.Next() {
	}
	if err := stream.Err(); err == nil {
		t.Fatal("expected a stream without response.completed to fail")
	}
}
