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
            if video.description <> invalid then desc = video.description

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
end sub
