package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"

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

	mux.HandleFunc("GET /api/dsn", func(w http.ResponseWriter, r *http.Request) {
		data, err := dsn.Fetch(baseURL)
		if err != nil {
			log.Printf("error fetching DSN data: %v", err)
			http.Error(w, "error fetching DSN data", http.StatusBadGateway)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(data)
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
