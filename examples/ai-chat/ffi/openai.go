package ffi

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"

	openai "github.com/openai/openai-go/v3"
	"github.com/openai/openai-go/v3/option"
	"github.com/openai/openai-go/v3/packages/ssestream"
	"github.com/openai/openai-go/v3/responses"
)

const Model = openai.ChatModelGPT4oMini

// Client keeps the OpenAI SDK behind an Ard-friendly API.
type Client struct {
	client openai.Client
}

// ChatRequest is the JSON payload accepted by POST /chat.
type ChatRequest struct {
	Prompt             string `json:"prompt"`
	PreviousResponseID string `json:"previous_response_id"`
}

// ChatStream exposes the SDK's generic stream through simple methods that map
// directly into Ard's Go interop.
type ChatStream struct {
	stream     *ssestream.Stream[responses.ResponseStreamEventUnion]
	delta      string
	responseID string
	completed  bool
	err        error
}

func NewClient(apiKey string) *Client {
	return &Client{client: openai.NewClient(
		option.WithAPIKey(apiKey),
		option.WithBaseURL("https://api.openai.com/v1/"),
		option.WithOrganization(""),
		option.WithProject(""),
	)}
}

func ParseChatRequest(body []byte) (*ChatRequest, error) {
	decoder := json.NewDecoder(bytes.NewReader(body))
	decoder.DisallowUnknownFields()

	var request ChatRequest
	if err := decoder.Decode(&request); err != nil {
		return nil, fmt.Errorf("invalid chat request: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return nil, errors.New("invalid chat request: expected one JSON object")
	}

	request.Prompt = strings.TrimSpace(request.Prompt)
	request.PreviousResponseID = strings.TrimSpace(request.PreviousResponseID)
	if request.Prompt == "" {
		return nil, errors.New("prompt is required")
	}
	if len(request.Prompt) > 8_000 {
		return nil, errors.New("prompt must be 8000 bytes or fewer")
	}
	return &request, nil
}

func (client *Client) Stream(ctx context.Context, prompt string, previousResponseID string) *ChatStream {
	params := responses.ResponseNewParams{
		Instructions:    openai.String("You are a concise, helpful assistant."),
		Input:           responses.ResponseNewParamsInputUnion{OfString: openai.String(prompt)},
		MaxOutputTokens: openai.Int(800),
		Model:           Model,
		Store:           openai.Bool(true),
	}
	if previousResponseID != "" {
		params.PreviousResponseID = openai.String(previousResponseID)
	}

	return &ChatStream{stream: client.client.Responses.NewStreaming(ctx, params)}
}

// Next advances to the next user-visible text delta. Other SDK events are
// consumed internally while response IDs and terminal errors are retained.
func (stream *ChatStream) Next() bool {
	for stream.stream.Next() {
		event := stream.stream.Current()
		switch event.Type {
		case "response.output_text.delta", "response.refusal.delta":
			if event.Delta != "" {
				stream.delta = event.Delta
				return true
			}
		case "response.completed":
			stream.responseID = event.Response.ID
			stream.completed = true
		case "response.failed", "response.incomplete":
			stream.err = fmt.Errorf("OpenAI response ended with %s", event.Type)
			return false
		case "error":
			stream.err = errors.New(event.Message)
			return false
		}
	}
	return false
}

func (stream *ChatStream) Delta() string {
	return stream.delta
}

func (stream *ChatStream) ResponseID() string {
	return stream.responseID
}

func (stream *ChatStream) Err() error {
	if stream.err != nil {
		return stream.err
	}
	if err := stream.stream.Err(); err != nil {
		return err
	}
	if !stream.completed || stream.responseID == "" {
		return errors.New("OpenAI stream ended before response completion")
	}
	return nil
}

func (stream *ChatStream) Close() {
	_ = stream.stream.Close()
}
