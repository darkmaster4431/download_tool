//go:build windows

package main

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"unicode/utf16"
	"unsafe"
)

const (
	wmDestroy      = 0x0002
	wmCommand      = 0x0111
	wmClose        = 0x0010
	wmAppProgress  = 0x8001
	wmAppDone      = 0x8002
	wsOverlapped   = 0x00CF0000
	wsVisible      = 0x10000000
	wsChild        = 0x40000000
	wsBorder       = 0x00800000
	esAutoHScroll  = 0x0080
	bsPushButton   = 0x00000000
	pbmSetRange32  = 0x0406
	pbmSetPos      = 0x0402
	swShow         = 5
	idURL          = 101
	idDownload     = 102
	idOpenFolder   = 103
	idHash         = 104
	cwUseDefault   = 0x80000000
	colorWindow    = 5
	defaultGUIFont = 17
)

var (
	user32   = syscall.NewLazyDLL("user32.dll")
	kernel32 = syscall.NewLazyDLL("kernel32.dll")
	shell32  = syscall.NewLazyDLL("shell32.dll")
	gdi32    = syscall.NewLazyDLL("gdi32.dll")
	comctl32 = syscall.NewLazyDLL("comctl32.dll")

	registerClassEx   = user32.NewProc("RegisterClassExW")
	createWindowEx    = user32.NewProc("CreateWindowExW")
	defWindowProc     = user32.NewProc("DefWindowProcW")
	showWindow        = user32.NewProc("ShowWindow")
	updateWindow      = user32.NewProc("UpdateWindow")
	getMessage        = user32.NewProc("GetMessageW")
	translateMessage  = user32.NewProc("TranslateMessage")
	dispatchMessage   = user32.NewProc("DispatchMessageW")
	postQuitMessage   = user32.NewProc("PostQuitMessage")
	postMessage       = user32.NewProc("PostMessageW")
	setWindowText     = user32.NewProc("SetWindowTextW")
	getWindowText     = user32.NewProc("GetWindowTextW")
	getWindowTextLen  = user32.NewProc("GetWindowTextLengthW")
	enableWindow      = user32.NewProc("EnableWindow")
	sendMessage       = user32.NewProc("SendMessageW")
	messageBox        = user32.NewProc("MessageBoxW")
	loadCursor        = user32.NewProc("LoadCursorW")
	getStockObject    = gdi32.NewProc("GetStockObject")
	getModuleHandle   = kernel32.NewProc("GetModuleHandleW")
	shellExecute      = shell32.NewProc("ShellExecuteW")
	initCommonControl = comctl32.NewProc("InitCommonControls")

	mainWindow  uintptr
	urlEdit     uintptr
	downloadBtn uintptr
	statusText  uintptr
	progressBar uintptr
	lastFile    string
	resultMu    sync.Mutex
	resultErr   error
)

type point struct{ x, y int32 }
type msg struct {
	hwnd           uintptr
	message        uint32
	wParam, lParam uintptr
	time           uint32
	pt             point
	private        uint32
}
type wndClassEx struct {
	size                               uint32
	style                              uint32
	wndProc                            uintptr
	clsExtra, wndExtra                 int32
	instance, icon, cursor, background uintptr
	menuName, className                *uint16
	iconSmall                          uintptr
}

func utf16Ptr(value string) *uint16 { return syscall.StringToUTF16Ptr(value) }

func createControl(class, text string, style uint32, x, y, width, height int32, parent uintptr, id int) uintptr {
	hwnd, _, _ := createWindowEx.Call(0, uintptr(unsafe.Pointer(utf16Ptr(class))), uintptr(unsafe.Pointer(utf16Ptr(text))),
		uintptr(style|wsChild|wsVisible), uintptr(x), uintptr(y), uintptr(width), uintptr(height), parent, uintptr(id), 0, 0)
	font, _, _ := getStockObject.Call(defaultGUIFont)
	sendMessage.Call(hwnd, 0x0030, font, 1)
	return hwnd
}

func windowText(hwnd uintptr) string {
	length, _, _ := getWindowTextLen.Call(hwnd)
	buffer := make([]uint16, length+1)
	getWindowText.Call(hwnd, uintptr(unsafe.Pointer(&buffer[0])), length+1)
	return string(utf16.Decode(buffer[:length]))
}

func setText(hwnd uintptr, value string) {
	setWindowText.Call(hwnd, uintptr(unsafe.Pointer(utf16Ptr(value))))
}

func wndProc(hwnd uintptr, message uint32, wParam, lParam uintptr) uintptr {
	switch message {
	case wmCommand:
		switch int(wParam & 0xffff) {
		case idDownload:
			startDownload(strings.TrimSpace(windowText(urlEdit)))
		case idOpenFolder:
			folder, _ := downloadFolder()
			shellExecute.Call(0, uintptr(unsafe.Pointer(utf16Ptr("open"))), uintptr(unsafe.Pointer(utf16Ptr(folder))), 0, 0, swShow)
		case idHash:
			showHash()
		}
		return 0
	case wmAppProgress:
		sendMessage.Call(progressBar, pbmSetPos, wParam, 0)
		return 0
	case wmAppDone:
		enableWindow.Call(downloadBtn, 1)
		resultMu.Lock()
		err := resultErr
		path := lastFile
		resultMu.Unlock()
		if err != nil {
			setText(statusText, "下载失败："+err.Error())
		} else {
			setText(statusText, "已完成："+path)
			sendMessage.Call(progressBar, pbmSetPos, 100, 0)
		}
		return 0
	case wmClose, wmDestroy:
		postQuitMessage.Call(0)
		return 0
	}
	result, _, _ := defWindowProc.Call(hwnd, uintptr(message), wParam, lParam)
	return result
}

func startDownload(raw string) {
	parsed, err := url.Parse(raw)
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") {
		setText(statusText, "请输入有效的 HTTP/HTTPS 链接")
		return
	}
	enableWindow.Call(downloadBtn, 0)
	setText(statusText, "正在连接…")
	sendMessage.Call(progressBar, pbmSetPos, 0, 0)
	go func() {
		path, err := download(raw, func(percent int) { postMessage.Call(mainWindow, wmAppProgress, uintptr(percent), 0) })
		resultMu.Lock()
		lastFile, resultErr = path, err
		resultMu.Unlock()
		postMessage.Call(mainWindow, wmAppDone, 0, 0)
	}()
}

func downloadFolder() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	folder := filepath.Join(home, "Downloads", "FlashFlow")
	return folder, os.MkdirAll(folder, 0755)
}

func safeName(raw string) string {
	name := filepath.Base(strings.ReplaceAll(raw, "\\", "/"))
	if name == "." || name == "/" || name == "" {
		name = "download.bin"
	}
	for _, ch := range []string{"<", ">", ":", "\"", "/", "\\", "|", "?", "*"} {
		name = strings.ReplaceAll(name, ch, "_")
	}
	return name
}

func newRequest(method, raw string) (*http.Request, error) {
	req, err := http.NewRequest(method, raw, nil)
	if err == nil {
		req.Header.Set("User-Agent", "FlashFlow-Windows/0.2")
		req.Header.Set("Accept-Encoding", "identity")
	}
	return req, err
}

func download(raw string, progress func(int)) (string, error) {
	client := &http.Client{Timeout: 0}
	head, _ := newRequest(http.MethodHead, raw)
	response, err := client.Do(head)
	if err != nil {
		return "", err
	}
	total := response.ContentLength
	ranges := strings.Contains(strings.ToLower(response.Header.Get("Accept-Ranges")), "bytes")
	finalURL := response.Request.URL
	response.Body.Close()

	folder, err := downloadFolder()
	if err != nil {
		return "", err
	}
	destination := filepath.Join(folder, safeName(finalURL.Path))
	if total > 2*1024*1024 && ranges {
		err = segmented(client, raw, destination, total, progress)
	} else {
		err = single(client, raw, destination, total, progress)
	}
	return destination, err
}

func segmented(client *http.Client, raw, destination string, total int64, progress func(int)) error {
	file, err := os.OpenFile(destination+".ffpart", os.O_CREATE|os.O_RDWR|os.O_TRUNC, 0644)
	if err != nil {
		return err
	}
	defer file.Close()
	if err = file.Truncate(total); err != nil {
		return err
	}

	type chunk struct{ start, end int64 }
	jobs := make(chan chunk)
	errCh := make(chan error, 2)
	var completed int64
	var workers sync.WaitGroup
	for i := 0; i < 2; i++ {
		workers.Add(1)
		go func() {
			defer workers.Done()
			for part := range jobs {
				req, requestErr := newRequest(http.MethodGet, raw)
				if requestErr != nil {
					errCh <- requestErr
					return
				}
				req.Header.Set("Range", fmt.Sprintf("bytes=%d-%d", part.start, part.end))
				resp, requestErr := client.Do(req)
				if requestErr != nil {
					errCh <- requestErr
					return
				}
				if resp.StatusCode != http.StatusPartialContent {
					resp.Body.Close()
					errCh <- errors.New("服务器拒绝分片请求")
					return
				}
				data, requestErr := io.ReadAll(resp.Body)
				resp.Body.Close()
				if requestErr != nil {
					errCh <- requestErr
					return
				}
				if int64(len(data)) != part.end-part.start+1 {
					errCh <- errors.New("分片长度不匹配")
					return
				}
				if _, requestErr = file.WriteAt(data, part.start); requestErr != nil {
					errCh <- requestErr
					return
				}
				value := atomic.AddInt64(&completed, int64(len(data)))
				progress(int(value * 100 / total))
			}
		}()
	}
	go func() {
		const size int64 = 4 * 1024 * 1024
		for start := int64(0); start < total; start += size {
			end := start + size - 1
			if end >= total {
				end = total - 1
			}
			jobs <- chunk{start, end}
		}
		close(jobs)
	}()
	done := make(chan struct{})
	go func() { workers.Wait(); close(done) }()
	select {
	case err = <-errCh:
		return err
	case <-done:
		if atomic.LoadInt64(&completed) != total {
			return errors.New("下载未完整结束")
		}
	}
	file.Close()
	os.Remove(destination)
	return os.Rename(destination+".ffpart", destination)
}

func single(client *http.Client, raw, destination string, total int64, progress func(int)) error {
	req, _ := newRequest(http.MethodGet, raw)
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	file, err := os.Create(destination + ".ffpart")
	if err != nil {
		return err
	}
	defer file.Close()
	buffer := make([]byte, 256*1024)
	var completed int64
	for {
		count, readErr := resp.Body.Read(buffer)
		if count > 0 {
			if _, err = file.Write(buffer[:count]); err != nil {
				return err
			}
			completed += int64(count)
			if total > 0 {
				progress(int(completed * 100 / total))
			}
		}
		if readErr == io.EOF {
			break
		}
		if readErr != nil {
			return readErr
		}
	}
	file.Close()
	os.Remove(destination)
	return os.Rename(destination+".ffpart", destination)
}

func showHash() {
	resultMu.Lock()
	path := lastFile
	resultMu.Unlock()
	if path == "" {
		setText(statusText, "尚没有已完成文件")
		return
	}
	go func() {
		file, err := os.Open(path)
		if err != nil {
			return
		}
		defer file.Close()
		hash := sha256.New()
		_, err = io.Copy(hash, file)
		if err != nil {
			return
		}
		digest := hex.EncodeToString(hash.Sum(nil))
		messageBox.Call(mainWindow, uintptr(unsafe.Pointer(utf16Ptr(digest))), uintptr(unsafe.Pointer(utf16Ptr("SHA-256"))), 0x40)
	}()
}

func main() {
	runtime.LockOSThread()
	initCommonControl.Call()
	instance, _, _ := getModuleHandle.Call(0)
	className := utf16Ptr("FlashFlowWindow")
	cursor, _, _ := loadCursor.Call(0, 32512)
	class := wndClassEx{size: uint32(unsafe.Sizeof(wndClassEx{})), wndProc: syscall.NewCallback(wndProc), instance: instance,
		cursor: cursor, background: colorWindow + 1, className: className}
	registerClassEx.Call(uintptr(unsafe.Pointer(&class)))

	mainWindow, _, _ = createWindowEx.Call(0, uintptr(unsafe.Pointer(className)), uintptr(unsafe.Pointer(utf16Ptr("FlashFlow Windows x64"))),
		wsOverlapped|wsVisible, cwUseDefault, cwUseDefault, 720, 270, 0, 0, instance, 0)
	createControl("STATIC", "下载链接", 0, 24, 24, 100, 24, mainWindow, 0)
	urlEdit = createControl("EDIT", "", wsBorder|esAutoHScroll, 24, 52, 655, 30, mainWindow, idURL)
	downloadBtn = createControl("BUTTON", "开始下载", bsPushButton, 24, 100, 110, 34, mainWindow, idDownload)
	createControl("BUTTON", "打开目录", bsPushButton, 144, 100, 110, 34, mainWindow, idOpenFolder)
	createControl("BUTTON", "SHA-256", bsPushButton, 264, 100, 110, 34, mainWindow, idHash)
	progressBar = createControl("msctls_progress32", "", 0, 24, 150, 655, 22, mainWindow, 0)
	sendMessage.Call(progressBar, pbmSetRange32, 0, 100)
	statusText = createControl("STATIC", "支持 HTTP/HTTPS，自动使用2连接分片", 0, 24, 184, 655, 36, mainWindow, 0)

	showWindow.Call(mainWindow, swShow)
	updateWindow.Call(mainWindow)
	var message msg
	for {
		result, _, _ := getMessage.Call(uintptr(unsafe.Pointer(&message)), 0, 0, 0)
		if int32(result) <= 0 {
			break
		}
		translateMessage.Call(uintptr(unsafe.Pointer(&message)))
		dispatchMessage.Call(uintptr(unsafe.Pointer(&message)))
	}
}
