sub init()
    m.top.functionName = "run"
end sub

sub run()
    print "APITask: Starting feed fetch..."
    
    ' Fetch JSON API containing all videos
    jsonUrl = "http://192.168.1.7:8945/api/v1/videos"
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
            if video.stream_url <> invalid then streamUrl = video.stream_url
            
            posterUrl = ""
            if video.thumbnail_url <> invalid then posterUrl = video.thumbnail_url

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

    ' Set up scoped observer for action requests (runs in Task thread)
    m.port = CreateObject("roMessagePort")
    m.top.observeFieldScoped("actionRequest", m.port)

    ' Keep Task alive to handle action requests
    while true
        msg = wait(0, m.port)
        if msg <> invalid
            if type(msg) = "roSGNodeEvent"
                field = msg.getField()
                if field = "actionRequest"
                    onActionRequest()
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
        url = "http://192.168.1.7:8945/api/v1/videos/" + videoId
        print "APITask: DELETE "; url
        request = CreateObject("roUrlTransfer")
        request.SetUrl(url)
        request.SetRequest("DELETE")
        response = request.PostFromString("")
        print "APITask: DELETE response code: "; response
    else if actionType = "ignore"
        url = "http://192.168.1.7:8945/api/v1/videos/" + videoId + "/ignore"
        print "APITask: POST "; url
        request = CreateObject("roUrlTransfer")
        request.SetUrl(url)
        request.SetRequest("POST")
        response = request.PostFromString("")
        print "APITask: POST response code: "; response
    end if
end sub
