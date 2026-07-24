sub init()
    m.top.functionName = "run"
end sub

sub run()
    print "APITask: Starting feed fetch..."
    
    ' Fetch JSON API containing all videos
    jsonUrl = m.top.serverURL + "/api/v1/videos"
    jsonTransfer = CreateObject("roUrlTransfer")
    jsonTransfer.SetUrl(jsonUrl)
    jsonResponse = jsonTransfer.GetToString()
    print "APITask: JSON response length: "; Len(jsonResponse)
    
    parsedJson = ParseJson(jsonResponse)
    if parsedJson = invalid 
        print "APITask ERROR: Failed to parse JSON API response"
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

            videoList.Push({
                title: video.title
                url: streamUrl
                id: video.id
                description: desc
                SDPosterUrl: posterUrl
                HDPosterUrl: posterUrl
            })
        end if
    end for

    print "APITask: Total compiled videos ready to send: "; videoList.Count()
    m.top.content = videoList

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
                    onActionRequest()
                else if field = "thumbnailRequest"
                    onThumbnailRequest()
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

sub onActionRequest()
    actionType = m.top.actionType
    videoId = m.top.actionVideoId

    if actionType = "delete"
        url = m.top.serverURL + "/api/v1/videos/" + videoId
        print "APITask: DELETE "; url
        request = CreateObject("roUrlTransfer")
        request.SetUrl(url)
        request.SetRequest("DELETE")
        response = request.PostFromString("")
        print "APITask: DELETE response code: "; response
    else if actionType = "ignore"
        url = m.top.serverURL + "/api/v1/videos/" + videoId + "/ignore"
        print "APITask: POST "; url
        request = CreateObject("roUrlTransfer")
        request.SetUrl(url)
        request.SetRequest("POST")
        response = request.PostFromString("")
        print "APITask: POST response code: "; response
    end if
end sub

sub onThumbnailRequest()
    request = m.top.thumbnailRequest
    if request = invalid then return

    url = request.url
    videoId = request.id
    if url = "" or url = invalid then return
    if videoId = "" or videoId = invalid then return

    localPath = "tmp:/thumb_" + videoId + ".jpg"
    transfer = CreateObject("roUrlTransfer")
    transfer.SetUrl(url)
    transfer.GetToFile(localPath)

    m.top.thumbnailResult = { localPath: localPath, id: videoId }
end sub

function rewriteURL(url as String) as String
    serverURL = m.top.serverURL

    ' Add http:// if no protocol specified
    if Left(serverURL, 7) <> "http://" and Left(serverURL, 8) <> "https://"
        serverURL = "http://" + serverURL
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
