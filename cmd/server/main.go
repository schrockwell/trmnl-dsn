package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"sync"
	"time"

	"trmnl-dsn/internal/dsn"
)

func main() {
	host := os.Getenv("HOST")
	if host == "" {
		host = "0.0.0.0"
	}
	port := os.Getenv("PORT")
	if port == "" {
		port = "3000"
	}
	baseURL := os.Getenv("BASE_URL")
	if baseURL == "" {
		baseURL = "http://localhost:" + port
	}

	mux := http.NewServeMux()

	var (
		cacheMu   sync.Mutex
		cachedJSON []byte
		cachedAt  time.Time
	)

	mux.HandleFunc("GET /api/dsn", func(w http.ResponseWriter, r *http.Request) {
		cacheMu.Lock()
		if cachedJSON != nil && time.Since(cachedAt) < time.Hour {
			body := cachedJSON
			cacheMu.Unlock()
			w.Header().Set("Content-Type", "application/json")
			w.Write(body)
			return
		}
		cacheMu.Unlock()

		data, err := dsn.Fetch(baseURL)
		if err != nil {
			log.Printf("error fetching DSN data: %v", err)
			http.Error(w, "error fetching DSN data", http.StatusBadGateway)
			return
		}

		body, err := json.Marshal(data)
		if err != nil {
			log.Printf("error encoding DSN data: %v", err)
			http.Error(w, "error encoding DSN data", http.StatusInternalServerError)
			return
		}

		cacheMu.Lock()
		cachedJSON = body
		cachedAt = time.Now()
		cacheMu.Unlock()

		w.Header().Set("Content-Type", "application/json")
		w.Write(body)
	})

	mux.Handle("GET /images/", http.StripPrefix("/images/", http.FileServer(http.Dir("public/images"))))

	mux.HandleFunc("GET /up", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, "ok")
	})

	mux.HandleFunc("GET /", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, "NASA Deep Space Network API. GET /api/dsn for data.")
	})

	addr := host + ":" + port
	log.Printf("listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, mux))
}
