package main

import (
	"apptransfer.local/appstorebridge/internal/bridge"
	"fmt"
	"os"
)

func main() {
	// Deliberately no global logger or verbose mode: only allowlisted protocol events leave this process.
	if len(os.Args) > 1 {
		fmt.Fprintln(os.Stderr, "AppStoreBridge accepts JSON Lines on stdin; no credential arguments are supported.")
		os.Exit(2)
	}
	server := bridge.NewServer(bridge.NewSystemSecrets(), bridge.NewCoreFactory(), os.Stdout)
	if err := server.Run(os.Stdin); err != nil {
		fmt.Fprintln(os.Stderr, "AppStoreBridge input stream failed.")
		os.Exit(1)
	}
}
