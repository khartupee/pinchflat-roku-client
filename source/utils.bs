' =============================================================================
' Pure utility functions — no Roku object dependencies.
' Used by APITask.brs and testable with Rooibos.
' =============================================================================

' --- String Cleaning ---

function cleanDescription(rawDesc as String) as String
    if rawDesc = "" or rawDesc = invalid then return ""

    desc = rawDesc

    ' Split by newlines and take the first non-empty paragraph
    lines = desc.Split(chr(10))
    firstParagraph = ""
    for each line in lines
        line = line.Trim()
        if line <> ""
            firstParagraph = line
            exit for
        end if
    end for

    if firstParagraph = ""
        return "No description available."
    end if

    ' Strip URLs (http and https)
    urlRegex = CreateObject("roRegex", "https?://[^ ]+", "")
    firstParagraph = urlRegex.ReplaceAll(firstParagraph, "")

    ' Collapse multiple spaces
    wsRegex = CreateObject("roRegex", "[ ]+", "")
    firstParagraph = wsRegex.ReplaceAll(firstParagraph, " ")

    firstParagraph = firstParagraph.Trim()

    ' If remaining content is too short, it was just boilerplate
    if Len(firstParagraph) < 20
        return "No description available."
    end if

    ' Truncate to 200 characters with ellipsis
    if Len(firstParagraph) > 200
        firstParagraph = Left(firstParagraph, 197) + "..."
    end if

    return firstParagraph
end function

' --- Date Formatting ---

function formatDate(dateStr as String) as String
    months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    clean = dateStr.Replace("Z", "")
    parts = clean.Split("T")
    if parts.Count() < 1 then return ""
    dateParts = parts[0].Split("-")
    if dateParts.Count() < 3 then return ""
    monthVal = Val(dateParts[1])
    if monthVal < 1 or monthVal > 12 then return ""
    monthIndex = monthVal - 1
    day = dateParts[2]
    year = dateParts[0]
    return months[monthIndex] + " " + day + ", " + year
end function

' --- Duration Formatting ---

function formatDuration(seconds as Integer) as String
    if seconds = 0 then return "0:00"
    hrs = seconds / 3600
    mins = (seconds Mod 3600) / 60
    secs = seconds Mod 60
    if hrs >= 1
        return Int(hrs).ToStr() + ":" + Right("0" + Int(mins).ToStr(), 2) + ":" + Right("0" + Int(secs).ToStr(), 2)
    end if
    return Int(mins).ToStr() + ":" + Right("0" + Int(secs).ToStr(), 2)
end function

' --- Base64 Encoding ---
' Manual base64 encoding (EncodeData not available on all Roku firmware)

function base64Encode(input as String) as String
    b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    output = ""
    i = 0
    len = Len(input)

    while i < len
        ' Read up to 3 bytes
        b0 = 0
        b1 = 0
        b2 = 0
        count = 0

        if i < len
            b0 = Asc(Mid(input, i + 1, 1))
            i = i + 1
            count = count + 1
        end if
        if i < len
            b1 = Asc(Mid(input, i + 1, 1))
            i = i + 1
            count = count + 1
        end if
        if i < len
            b2 = Asc(Mid(input, i + 1, 1))
            i = i + 1
            count = count + 1
        end if

        ' Encode 3 bytes into 4 base64 characters
        triple = (b0 * 65536) + (b1 * 256) + b2
        c1 = Int(triple / 262144) Mod 64
        c2 = Int(triple / 4096) Mod 64
        c3 = Int(triple / 64) Mod 64
        c4 = triple Mod 64
        output = output + Mid(b64chars, c1 + 1, 1)
        output = output + Mid(b64chars, c2 + 1, 1)
        output = output + Mid(b64chars, c3 + 1, 1)
        output = output + Mid(b64chars, c4 + 1, 1)

        ' Add padding for incomplete groups
        if count < 3
            ' Remove the extra chars and add = padding
            output = Left(output, Len(output) - (3 - count))
            if count = 1 then output = output + "=="
            if count = 2 then output = output + "="
        end if
    end while

    return output
end function

' --- URL Rewriting ---
' Extracts the path from a URL and prepends the server URL.
' Takes serverURL as a parameter so it can be tested without Roku objects.

function rewriteURL(url as String, serverURL as String) as String
    ' Add https:// if no protocol specified
    if Left(serverURL, 7) <> "http://" and Left(serverURL, 8) <> "https://"
        serverURL = "https://" + serverURL
    end if

    ' Extract path from the original URL (everything after the host:port) and prepend serverURL
    regex = CreateObject("roRegex", "^https?://[^/]+(/.*)$", "")
    match = regex.Match(url)
    if match.Count() > 1
        path = match[1]
        if Right(serverURL, 1) = "/"
            serverURL = Left(serverURL, Len(serverURL) - 1)
        end if
        return serverURL + path
    end if

    return url
end function

' --- URL Sanitization ---
' Strip "user:pass@" from a URL for safe logging.
' Returns the URL unchanged if no credentials are present.

function stripAuthFromURL(url as String) as String
    if url = "" or url = invalid then return url
    ' Match scheme://user:pass@host — if user:pass present, remove it
    regex = CreateObject("roRegex", "^(https?)://[^@/]+@([^/].*)$", "")
    match = regex.Match(url)
    if match <> invalid and match.Count() >= 3
        scheme = match[1]
        rest = match[2]
        return scheme + "://" + rest
    end if
    return url
end function
