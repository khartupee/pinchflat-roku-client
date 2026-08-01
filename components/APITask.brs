sub init()
    m.top.functionName = "run"
end sub

sub run()
    print "APITask: Starting feed fetch..."
    
    ' Fetch JSON API containing all videos
    jsonUrl = m.top.serverURL + "/api/v1/videos"
    jsonTransfer = CreateObject("roUrlTransfer")
    setupAuth(jsonTransfer)
    jsonTransfer.SetUrl(jsonUrl)
    jsonResponse = jsonTransfer.GetToString()
    print "APITask: JSON response length: "; Len(jsonResponse)
    
    parsedJson = ParseJson(jsonResponse)
    if parsedJson = invalid or jsonResponse = ""
        ' API call failed - check if server is reachable but running wrong version
        checkTransfer = CreateObject("roUrlTransfer")
        setupAuth(checkTransfer)
        checkTransfer.SetUrl(m.top.serverURL + "/healthcheck")
        checkResponse = checkTransfer.GetToString()

        if checkResponse <> "" and checkResponse <> invalid
            ' Server responded to healthcheck - it's Pinchflat but missing Roku API or auth failed
            m.top.errorMessage = "AUTH_REQUIRED"
        else
            ' Server unreachable or not Pinchflat
            errorMsg = "Could not connect to server at " + m.top.serverURL + Chr(10) + Chr(10) + "Please check your server URL in Settings."
            m.top.errorMessage = errorMsg
        end if

        print "APITask ERROR: "; m.top.errorMessage
        parsedJson = []
    end if

    videoList = []
    for each video in parsedJson
        if video.title <> invalid and video.id <> invalid
            streamUrl = ""
            if video.stream_url <> invalid then streamUrl = rewriteURL(video.stream_url)
            
            posterUrl = ""
            if video.thumbnail_url <> invalid then posterUrl = rewriteURL(video.thumbnail_url)

            desc = ""
            if video.description <> invalid then desc = cleanDescription(video.description)

            playPos = 0
            if video.playback_position_seconds <> invalid then playPos = Int(video.playback_position_seconds)

            vidDur = 0
            if video.duration_seconds <> invalid then vidDur = Int(video.duration_seconds)

            srcName = ""
            if video.source_name <> invalid then srcName = video.source_name

            srcId = 0
            if video.source_id <> invalid then srcId = video.source_id

            uploadDate = ""
            if video.uploaded_at <> invalid then uploadDate = formatDate(video.uploaded_at)

            videoList.Push({
                title: video.title
                url: streamUrl
                id: video.id
                description: desc
                SDPosterUrl: posterUrl
                HDPosterUrl: posterUrl
                playbackPosition: playPos
                durationSeconds: vidDur
                sourceName: srcName
                sourceId: srcId
                uploadDate: uploadDate
            })
        end if
    end for

    print "APITask: Total compiled videos ready to send: "; videoList.Count()
    m.top.content = videoList

    ' Fetch sources for header descriptions
    sourcesUrl = m.top.serverURL + "/api/v1/sources"
    sourcesTransfer = CreateObject("roUrlTransfer")
    setupAuth(sourcesTransfer)
    sourcesTransfer.SetUrl(sourcesUrl)
    sourcesResponse = sourcesTransfer.GetToString()
    if sourcesResponse <> "" and sourcesResponse <> invalid
        sourcesJson = ParseJson(sourcesResponse)
        if sourcesJson <> invalid
            m.top.sources = sourcesJson
            print "APITask: Loaded "; sourcesJson.Count(); " sources."
        end if
    end if

    ' Set up scoped observers for action and thumbnail requests (runs in Task thread)
    m.port = CreateObject("roMessagePort")
    m.top.observeFieldScoped("actionRequest", m.port)
    m.top.observeFieldScoped("thumbnailRequest", m.port)

    ' Keep Task alive to handle action and thumbnail requests
    while true
        msg = wait(0, m.port)
        if msg <> invalid
            if type(msg) = "roSGNodeEvent"
                field = msg.getField()
                if field = "actionRequest"
                    onActionRequest(msg)
                else if field = "thumbnailRequest"
                    onThumbnailRequest(msg)
                end if
            end if
        end if
    end while
end sub

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

sub onActionRequest(event as Object)
    requestData = event.GetData()
    if requestData = invalid then return

    actionType = requestData.type
    videoId = requestData.videoId

    if actionType = "delete"
        url = m.top.serverURL + "/api/v1/videos/" + videoId
        print "APITask: DELETE "; stripAuthFromURL(url)
        request = CreateObject("roUrlTransfer")
        setupAuth(request)
        request.SetUrl(url)
        request.SetRequest("DELETE")
        response = request.PostFromString("")
        print "APITask: DELETE response code: "; response
    else if actionType = "ignore"
        url = m.top.serverURL + "/api/v1/videos/" + videoId + "/ignore"
        print "APITask: POST "; stripAuthFromURL(url)
        request = CreateObject("roUrlTransfer")
        setupAuth(request)
        request.SetUrl(url)
        request.SetRequest("POST")
        response = request.PostFromString("")
        print "APITask: POST response code: "; response
    else if actionType = "save_progress"
        position = requestData.position
        if position = invalid then position = 0
        url = m.top.serverURL + "/api/v1/videos/" + videoId + "/progress"
        print "APITask: PATCH progress "; stripAuthFromURL(url); " position="; position
        request = CreateObject("roUrlTransfer")
        setupAuth(request)
        request.SetUrl(url)
        request.SetRequest("PATCH")
        request.AddHeader("Content-Type", "application/json")
        response = request.PostFromString("{""position"":" + position.toStr() + "}")
    end if
end sub

sub onThumbnailRequest(event as Object)
    request = event.GetData()
    if request = invalid then return

    url = request.url
    videoId = request.id
    if url = "" or url = invalid then return
    if videoId = "" or videoId = invalid then return

    localPath = "tmp:/thumb_" + videoId + ".jpg"
    transfer = CreateObject("roUrlTransfer")
    setupAuth(transfer)
    transfer.SetUrl(url)
    transfer.GetToFile(localPath)

    m.top.thumbnailResult = { localPath: localPath, id: videoId }
end sub

' Adds Basic Auth header to a roUrlTransfer if credentials are configured.
' Does nothing if username is empty (basic auth not configured).
sub setupAuth(request as Object)
    username = m.top.basicAuthUsername
    if username = "" or username = invalid then return

    password = m.top.basicAuthPassword
    if password = invalid then password = ""

    ' Build base64-encoded "username:password"
    credentials = username + ":" + password
    b64 = base64Encode(credentials)

    request.AddHeader("Authorization", "Basic " + b64)
end sub

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

function rewriteURL(url as String) as String
    serverURL = m.top.serverURL

    ' Add http:// if no protocol specified
    if Left(serverURL, 7) <> "http://" and Left(serverURL, 8) <> "https://"
        serverURL = "https://" + serverURL
    end if

    ' Embed credentials in URL if basic auth is configured (needed for video player)
    username = m.top.basicAuthUsername
    if username <> "" and username <> invalid
        password = m.top.basicAuthPassword
        if password = invalid then password = ""
        ' Extract scheme and path from serverURL
        scheme = ""
        hostPort = serverURL
        if Left(serverURL, 8) = "https://"
            scheme = "https://"
            hostPort = Right(serverURL, Len(serverURL) - 8)
        else if Left(serverURL, 7) = "http://"
            scheme = "http://"
            hostPort = Right(serverURL, Len(serverURL) - 7)
        end if
        serverURL = scheme + username + ":" + password + "@" + hostPort
    end if

    ' Extract path from the original URL (everything after the host:port)
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

' Strip "user:pass@" from a URL for safe logging. Returns the URL unchanged if no credentials are present.
function stripAuthFromURL(url as String) as String
    if url = "" or url = invalid then return url
    ' Match scheme://user:pass@host or scheme://host — if user:pass present, remove it
    regex = CreateObject("roRegex", "^(https?)://[^@/]+@([^/].*)$", "")
    if regex.Match(url) <> invalid
        scheme = regex.Match(url)[1]
        rest = regex.Match(url)[2]
        return scheme + "://" + rest
    end if
    return url
end function
