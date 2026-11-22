#Requires AutoHotkey v2.0
; Helpers for window-picker.ahk: a JSON parser, flattening of
; `glazewm query workspaces`, and the fuzzy filter. No GUI or process calls,
; so scripts/test-glazewm-window-picker.ahk can run them headless.

; Parses JSON text. Objects become Map, arrays Array, null "" (empty string),
; true/false 1/0. Throws Error on malformed input.
PickerParseJson(text) {
    pos := 1
    value := PickerJsonValue(text, &pos)
    PickerJsonSkipSpace(text, &pos)
    if (pos <= StrLen(text))
        throw Error("Unexpected text after the JSON value at " pos)
    return value
}

PickerJsonSkipSpace(text, &pos) {
    if RegExMatch(text, "\G[ \t\r\n]+", &m, pos)
        pos += m.Len
}

PickerJsonValue(text, &pos) {
    static literals := Map("true", true, "false", false, "null", "")
    PickerJsonSkipSpace(text, &pos)
    ch := SubStr(text, pos, 1)
    if (ch = "{")
        return PickerJsonObject(text, &pos)
    if (ch = "[")
        return PickerJsonArray(text, &pos)
    if (ch = '"')
        return PickerJsonString(text, &pos)
    if RegExMatch(text, "\G-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?", &m, pos) {
        pos += m.Len
        return m[0] + 0
    }
    for literal, value in literals {
        if (SubStr(text, pos, StrLen(literal)) == literal) {
            pos += StrLen(literal)
            return value
        }
    }
    throw Error("Unexpected JSON at " pos)
}

PickerJsonObject(text, &pos) {
    obj := Map()
    pos += 1
    PickerJsonSkipSpace(text, &pos)
    if (SubStr(text, pos, 1) = "}") {
        pos += 1
        return obj
    }
    loop {
        PickerJsonSkipSpace(text, &pos)
        if (SubStr(text, pos, 1) != '"')
            throw Error("Expected an object key at " pos)
        key := PickerJsonString(text, &pos)
        PickerJsonSkipSpace(text, &pos)
        if (SubStr(text, pos, 1) != ":")
            throw Error("Expected ':' at " pos)
        pos += 1
        obj[key] := PickerJsonValue(text, &pos)
        PickerJsonSkipSpace(text, &pos)
        separator := SubStr(text, pos, 1)
        pos += 1
        if (separator = "}")
            return obj
        if (separator != ",")
            throw Error("Expected ',' or '}' at " (pos - 1))
    }
}

PickerJsonArray(text, &pos) {
    arr := []
    pos += 1
    PickerJsonSkipSpace(text, &pos)
    if (SubStr(text, pos, 1) = "]") {
        pos += 1
        return arr
    }
    loop {
        arr.Push(PickerJsonValue(text, &pos))
        PickerJsonSkipSpace(text, &pos)
        separator := SubStr(text, pos, 1)
        pos += 1
        if (separator = "]")
            return arr
        if (separator != ",")
            throw Error("Expected ',' or ']' at " (pos - 1))
    }
}

; pos is at the opening quote; returns the decoded string.
PickerJsonString(text, &pos) {
    out := ""
    pos += 1
    loop {
        RegExMatch(text, '\G[^"\\]*', &m, pos)
        out .= m[0]
        pos += m.Len
        ch := SubStr(text, pos, 1)
        if (ch = '"') {
            pos += 1
            return out
        }
        if (ch != "\")
            throw Error("Unterminated JSON string")
        escaped := SubStr(text, pos + 1, 1)
        switch escaped, true {
            case '"', "\", "/": out .= escaped
            case "b": out .= Chr(8)
            case "f": out .= Chr(12)
            case "n": out .= "`n"
            case "r": out .= "`r"
            case "t": out .= "`t"
            case "u":
                hex := SubStr(text, pos + 2, 4)
                if !RegExMatch(hex, "^[0-9A-Fa-f]{4}$")
                    throw Error("Bad \u escape at " pos)
                ; Surrogate pairs arrive as two escapes; AutoHotkey strings
                ; are UTF-16, so appending both halves yields the character.
                out .= Chr(Integer("0x" hex))
                pos += 4
            default:
                throw Error("Bad escape at " pos)
        }
        pos += 2
    }
}

; Flattens `glazewm query workspaces` output into one Map per window with id,
; workspace, displayed (whether that workspace is shown on a display),
; process and title, in GlazeWM's tree order.
PickerCollectWindows(response) {
    windows := []
    for workspace in response["data"]["workspaces"]
        PickerCollectChildren(workspace["children"], workspace, windows)
    return windows
}

PickerCollectChildren(children, workspace, windows) {
    for child in children {
        if (child["type"] == "window")
            windows.Push(Map(
                "id", child["id"],
                "workspace", workspace["name"],
                "displayed", workspace["isDisplayed"],
                "process", child["processName"],
                "title", child["title"]))
        else if child.Has("children")
            PickerCollectChildren(child["children"], workspace, windows)
    }
}

; Keeps the windows whose "workspace process title" text contains every
; whitespace-separated query term as a case-insensitive subsequence. Tightest
; matches come first; ties keep input order. A blank query keeps everything.
PickerFilterWindows(windows, query) {
    terms := []
    for term in StrSplit(query, [" ", "`t"])
        if (term != "")
            terms.Push(term)
    if !terms.Length
        return windows.Clone()

    scored := []
    for window in windows {
        haystack := window["workspace"] " " window["process"] " " window["title"]
        total := 0
        for term in terms {
            score := PickerSubsequenceScore(haystack, term)
            if (score < 0) {
                total := -1
                break
            }
            total += score
        }
        if (total >= 0)
            scored.Push([total, window])
    }

    ; Stable insertion sort by score; the list is a few dozen windows.
    loop scored.Length - 1 {
        entry := scored[A_Index + 1]
        j := A_Index
        while (j >= 1 && scored[j][1] > entry[1]) {
            scored[j + 1] := scored[j]
            j -= 1
        }
        scored[j + 1] := entry
    }

    result := []
    for entry in scored
        result.Push(entry[2])
    return result
}

; Score of the tightest case-insensitive subsequence match of term in haystack:
; skipped characters inside the match times 1000, plus the match start, so a
; contiguous match beats a scattered one and an earlier match wins ties.
; Returns -1 when term is not a subsequence.
PickerSubsequenceScore(haystack, term) {
    best := -1
    termLength := StrLen(term)
    start := 0
    while (start := InStr(haystack, SubStr(term, 1, 1), false, start + 1)) {
        pos := start
        loop termLength - 1 {
            pos := InStr(haystack, SubStr(term, A_Index + 1, 1), false, pos + 1)
            if !pos
                break
        }
        ; A later start cannot complete a match this one could not.
        if !pos
            break
        score := (pos - start + 1 - termLength) * 1000 + start
        if (best < 0 || score < best)
            best := score
    }
    return best
}
