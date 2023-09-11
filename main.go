package main

import (
	"flag"
	"log"
	"net/http"
	"os"

	"github.com/gorilla/mux"
)

func main() {
	var listen string

	flag.StringVar(&listen, "listen", ":8085", "port to listen to")
	flag.Parse()

	m := mux.NewRouter()

	r := m.PathPrefix("/sgr").Subrouter()

	// Main Service Endpoints
	r.HandleFunc("/config", GetConfig).Methods("GET")
	//r.HandleFunc("/config", UpdateConfig).Methods("POST")
	r.HandleFunc("/instances", GetInstances).Methods("GET")

	log.Fatal(http.ListenAndServe(listen, r))
}

func GetConfig(w http.ResponseWriter, r *http.Request) {
	data, err := os.ReadFile("static/test/config.json")

	if err != nil {
		http.Error(w, "Failed to read JSON file", http.StatusInternalServerError)
		return
	}

	// Set the content type header to indicate that the response is in JSON format
	w.Header().Set("Content-Type", "application/json")

	// Write the JSON data to the response
	w.Write(data)
}

func GetInstances(w http.ResponseWriter, r *http.Request) {
	data, err := os.ReadFile("static/test/instances.json")

	if err != nil {
		http.Error(w, "Failed to read JSON file", http.StatusInternalServerError)
		return
	}

	// Set the content type header to indicate that the response is in JSON format
	w.Header().Set("Content-Type", "application/json")

	// Write the JSON data to the response
	w.Write(data)
}
