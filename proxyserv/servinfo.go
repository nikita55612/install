package main

import (
	"flag"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"sync/atomic"
	"time"
)

const DEFAULT_HOST = ""
const DEFAULT_PORT = 8090

var tsLast atomic.Int64
var infoCache = ""

func execCommand(name string, arg ...string) string {
	cmd := exec.Command(name, arg...)
	stdout, err := cmd.Output()

	if err != nil {
		fmt.Println(err.Error())
		return ""
	}

	return string(stdout)
}

func info(w http.ResponseWriter, req *http.Request) {
	tsNow := time.Now().Unix()
	if tsNow-tsLast.Load() <= 2 {
		fmt.Fprintf(w, infoCache)
		return
	}

	tsLast.Store(tsNow)

	infoCache = ""
	infoCache += strings.ReplaceAll(execCommand("fastfetch", "--pipe", "--structure", "separator:os:separator:host:kernel:uptime:packages:shell:de:wm:wmtheme:theme:icons:font:cpu:gpu:memory:disk:localip"), "[34C", "")

	fmt.Fprintf(w, infoCache)

}

func main() {
	fmt.Println(len(os.Args), os.Args)

	host := flag.String("host", DEFAULT_HOST, "host 0.0.0.0")
	port := flag.Int("port", DEFAULT_PORT, "port 8090")

	flag.Parse()

	fmt.Println(*host, *port)

	http.HandleFunc("/info", info)

	addr := fmt.Sprintf("%s:%d", *host, *port)
	http.ListenAndServe(addr, nil)
}
