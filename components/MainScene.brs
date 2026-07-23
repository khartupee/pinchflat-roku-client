sub init()
    print "MainScene: init() started"

    ' Find UI components
    m.videoList = m.top.findNode("videoList")
    m.videoPlayer = m.top.findNode("videoPlayer")
    m.previewPoster = m.top.findNode("previewPoster")
    m.previewTitle = m.top.findNode("previewTitle")
    m.previewDescription = m.top.findNode("previewDescription")

    if m.videoList <> invalid
        m.videoList.setFocus(true)
        m.videoList.observeField("itemSelected", "onVideoSelected")
        m.videoList.observeField("itemFocused", "onVideoFocused")
        print "MainScene: 'videoList' node found and focused."
    else
        print "ERROR: Could not find 'videoList' node in MainScene.xml."
    end if

    loadFeed()
end sub

sub loadFeed()
    print "MainScene: Spawning APITask..."
    m.apiTask = CreateObject("roSGNode", "APITask")
    m.apiTask.observeField("content", "onFeedLoaded")
    m.apiTask.control = "RUN"
end sub

sub onFeedLoaded()
    print "MainScene: onFeedLoaded() triggered!"
    newContent = m.apiTask.content
    if newContent <> invalid and newContent.Count() > 0
        print "MainScene: Received "; newContent.Count(); " items from APITask."
        rootNode = CreateObject("roSGNode", "ContentNode")
        for each item in newContent
            node = rootNode.CreateChild("ContentNode")
            node.title = item.title
            node.url = item.url
            node.id = item.id
            node.description = item.description
            node.SDPosterUrl = item.SDPosterUrl
            node.HDPosterUrl = item.HDPosterUrl
        end for
        
        m.videoContent = rootNode
        if m.videoList <> invalid
            m.videoList.content = m.videoContent
            print "MainScene: Bound content to videoList node successfully."
            
            ' Set initial preview
            onVideoFocused()
        end if
    else
        print "MainScene WARNING: APITask returned empty or invalid content."
    end if
end sub

sub onVideoSelected()
    if m.videoList = invalid then return
    selectedIndex = m.videoList.itemSelected
    if selectedIndex >= 0
        playVideo(selectedIndex)
    end if
end sub

sub onVideoFocused()
    if m.videoList = invalid or m.videoContent = invalid then return
    focusedIndex = m.videoList.itemFocused
    if focusedIndex >= 0 and focusedIndex < m.videoContent.GetChildCount()
        itemNode = m.videoContent.GetChild(focusedIndex)
        if itemNode <> invalid
            if m.previewPoster <> invalid
                m.previewPoster.uri = itemNode.SDPosterUrl
            end if
            if m.previewTitle <> invalid
                m.previewTitle.text = itemNode.title
            end if
            if m.previewDescription <> invalid
                desc = itemNode.description
                if desc = invalid or desc = "" then desc = "No description available."
                m.previewDescription.text = desc
            end if
        end if
    end if
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    handled = false
    if press then
        ' Handle back button to exit video player
        if m.videoPlayer <> invalid and m.videoPlayer.visible = true
            if key = "back"
                print "Closing video player..."
                m.videoPlayer.control = "stop"
                m.videoPlayer.visible = false
                m.videoList.setFocus(true)
                handled = true
            end if
        else if key = "options"
            if m.videoList <> invalid and m.videoContent <> invalid
                focusedIndex = m.videoList.itemFocused
                if focusedIndex >= 0
                    itemNode = m.videoContent.GetChild(focusedIndex)
                    if itemNode <> invalid
                        showActionDialog(focusedIndex, itemNode.id.toStr(), itemNode.title)
                        handled = true
                    end if
                end if
            end if
        end if
    end if
    return handled
end function

sub showActionDialog(itemIndex as Integer, videoId as String, videoTitle as String)
    scene = m.top.getScene()
    scene.dialog = invalid

    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.title = "Manage Video"
    dialog.message = [videoTitle]
    dialog.buttons = ["Play", "Delete File", "Delete & Ignore", "Cancel"]

    dialog.addFields({
        itemIndex: itemIndex
        videoId: videoId
    })

    dialog.observeField("buttonSelected", "onActionSelected")
    scene.dialog = dialog
end sub

sub onActionSelected()
    scene = m.top.getScene()
    dialog = scene.dialog
    if dialog = invalid then return

    buttonIndex = dialog.buttonSelected
    itemIndex = dialog.itemIndex
    videoId = dialog.videoId

    scene.dialog = invalid

    if buttonIndex = 0
        playVideo(itemIndex)
    else if buttonIndex = 1
        deleteVideoFromServer(itemIndex, videoId)
    else if buttonIndex = 2
        deleteAndIgnoreVideoFromServer(itemIndex, videoId)
    end if
end sub

sub deleteVideoFromServer(itemIndex as Integer, videoId as String)
    m.apiTask.actionType = "delete"
    m.apiTask.actionVideoId = videoId
    m.apiTask.actionRequest = "go"
    removeVideoFromList(itemIndex)
end sub

sub deleteAndIgnoreVideoFromServer(itemIndex as Integer, videoId as String)
    m.apiTask.actionType = "ignore"
    m.apiTask.actionVideoId = videoId
    m.apiTask.actionRequest = "go"
    removeVideoFromList(itemIndex)
end sub

sub removeVideoFromList(itemIndex as Integer)
    if m.videoContent <> invalid
        childNode = m.videoContent.GetChild(itemIndex)
        if childNode <> invalid
            m.videoContent.removeChild(childNode)
        end if
    end if

    ' Select next or previous item if available
    if m.videoList <> invalid and m.videoContent <> invalid
        count = m.videoContent.GetChildCount()
        if count > 0
            if itemIndex >= count then itemIndex = count - 1
            m.videoList.jumpToItem = itemIndex
        end if
    end if

    onVideoFocused()
end sub

sub playVideo(itemIndex as Integer)
    if m.videoContent <> invalid and m.videoPlayer <> invalid
        itemNode = m.videoContent.GetChild(itemIndex)
        if itemNode <> invalid and itemNode.url <> "" and itemNode.url <> invalid
            print "Launching player for URL: "; itemNode.url

            ' Store current video info for post-play dialog
            m.currentPlayIndex = itemIndex
            m.currentPlayId = itemNode.id.toStr()

            videoContent = CreateObject("roSGNode", "ContentNode")
            videoContent.url = itemNode.url
            videoContent.title = itemNode.title
            videoContent.streamFormat = "mp4"

            m.videoPlayer.content = videoContent
            m.videoPlayer.visible = true
            m.videoPlayer.setFocus(true)
            m.videoPlayer.control = "play"

            m.videoPlayer.observeField("state", "onVideoPlayerStateChange")
        end if
    end if
end sub

sub onVideoPlayerStateChange()
    if m.videoPlayer <> invalid
        state = m.videoPlayer.state
        print "Video player state changed to: "; state
        if state = "finished"
            m.videoPlayer.control = "stop"
            m.videoPlayer.visible = false
            showPostPlayDialog()
        else if state = "error"
            m.videoPlayer.control = "stop"
            m.videoPlayer.visible = false
            m.videoList.setFocus(true)
        end if
    end if
end sub

sub showPostPlayDialog()
    scene = m.top.getScene()
    scene.dialog = invalid

    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.title = "Video Finished"
    dialog.message = "Delete and Ignore this video?"
    dialog.buttons = ["Yes", "No"]

    dialog.addFields({
        itemIndex: m.currentPlayIndex
        videoId: m.currentPlayId
    })

    dialog.observeField("buttonSelected", "onPostPlayActionSelected")
    scene.dialog = dialog
end sub

sub onPostPlayActionSelected()
    scene = m.top.getScene()
    dialog = scene.dialog
    if dialog = invalid then return

    buttonIndex = dialog.buttonSelected
    itemIndex = dialog.itemIndex
    videoId = dialog.videoId

    scene.dialog = invalid

    if buttonIndex = 0
        deleteAndIgnoreVideoFromServer(itemIndex, videoId)
    end if

    m.videoList.setFocus(true)
end sub
