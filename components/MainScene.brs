sub init()
    print "MainScene: init() started"

    ' Find UI components
    m.videoList = m.top.findNode("videoList")
    m.videoPlayer = m.top.findNode("videoPlayer")
    m.previewPoster = m.top.findNode("previewPoster")
    m.previewTitle = m.top.findNode("previewTitle")
    m.previewDescription = m.top.findNode("previewDescription")
    m.posterDelayTimer = m.top.findNode("posterDelayTimer")
    m.emptyStateLabel = m.top.findNode("emptyStateLabel")

    ' Load settings from registry
    loadSettings()

    ' Thumbnail cache: maps video ID to local file path
    m.thumbnailCache = {}
    m.feedLoaded = false
    m.launchBeaconFired = false

    if m.videoList <> invalid
        m.videoList.setFocus(true)
        m.videoList.observeField("itemSelected", "onVideoSelected")
        m.videoList.observeField("itemFocused", "onVideoFocused")
        print "MainScene: 'videoList' node found and focused."
    else
        print "ERROR: Could not find 'videoList' node in MainScene.xml."
    end if

    if m.posterDelayTimer <> invalid
        m.posterDelayTimer.observeField("fire", "onPosterDelayTimerFire")
    end if

    ' Deep linking: create InputTask to listen for roInput events
    m.inputTask = CreateObject("roSGNode", "InputTask")
    m.inputTask.observeField("inputData", "onDeepLinkInput")
    m.inputTask.control = "RUN"

    ' If no server URL configured, prompt user to set one
    if m.serverURL = ""
        showServerInputDialog()
    else
        loadFeed()
    end if
end sub

sub loadFeed()
    print "MainScene: Spawning APITask..."
    m.feedLoaded = true
    m.apiTask = CreateObject("roSGNode", "APITask")
    m.apiTask.observeField("content", "onFeedLoaded")
    m.apiTask.observeField("thumbnailResult", "onThumbnailLoaded")
    m.apiTask.observeField("errorMessage", "onAPIError")
    m.apiTask.serverURL = m.serverURL
    m.apiTask.control = "RUN"
end sub

sub onFeedLoaded()
    print "MainScene: onFeedLoaded() triggered!"
    newContent = m.apiTask.content
    if newContent <> invalid and newContent.Count() > 0
        print "MainScene: Received "; newContent.Count(); " items from APITask."

        ' Hide empty state if showing
        if m.emptyStateLabel <> invalid then m.emptyStateLabel.visible = false

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

        ' Fire AppLaunchComplete beacon (only once per launch)
        if not m.launchBeaconFired
            m.top.signalBeacon("AppLaunchComplete")
            m.launchBeaconFired = true
        end if
    else
        print "MainScene WARNING: APITask returned empty or invalid content."
        if m.emptyStateLabel <> invalid
            m.emptyStateLabel.text = "No videos found on server" + Chr(10) + m.serverURL
            m.emptyStateLabel.visible = true
        end if
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
    
    ' Postpone image fetching while scrolling.
    ' Reset timer on every navigation event.
    if m.posterDelayTimer <> invalid
        m.posterDelayTimer.control = "STOP"
        m.posterDelayTimer.control = "START"
    end if
end sub

sub onPosterDelayTimerFire()
    if m.videoList = invalid or m.videoContent = invalid then return
    focusedIndex = m.videoList.itemFocused
    if focusedIndex >= 0 and focusedIndex < m.videoContent.GetChildCount()
        itemNode = m.videoContent.GetChild(focusedIndex)
        if itemNode <> invalid
            if m.previewTitle <> invalid
                m.previewTitle.text = itemNode.title
            end if
            if m.previewDescription <> invalid
                desc = itemNode.description
                if desc = invalid or desc = "" then desc = "No description available."
                m.previewDescription.text = desc
            end if

            ' Lazy-load thumbnail
            videoId = itemNode.id.toStr()
            if videoId <> "" and videoId <> "invalid"
                if m.thumbnailCache.DoesExist(videoId)
                    ' Already cached, use local path
                    if m.previewPoster <> invalid
                        m.previewPoster.uri = m.thumbnailCache[videoId]
                    end if
                else if itemNode.SDPosterUrl <> "" and itemNode.SDPosterUrl <> invalid
                    ' Request download from APITask
                    m.pendingThumbnailId = videoId
                    m.apiTask.thumbnailRequest = { url: itemNode.SDPosterUrl, id: videoId }
                end if
            end if
        end if
    else
        ' No items - clear the preview panel
        if m.previewTitle <> invalid then m.previewTitle.text = ""
        if m.previewDescription <> invalid then m.previewDescription.text = ""
        if m.previewPoster <> invalid then m.previewPoster.uri = ""
    end if
end sub

sub onThumbnailLoaded(event as Object)
    result = event.GetData()
    if result = invalid or result.id = invalid then return

    videoId = result.id
    localPath = result.localPath

    ' Cache the local path
    m.thumbnailCache[videoId] = localPath

    ' Update poster if this is still the focused item
    if m.videoList <> invalid and m.videoContent <> invalid
        focusedIndex = m.videoList.itemFocused
        if focusedIndex >= 0 and focusedIndex < m.videoContent.GetChildCount()
            itemNode = m.videoContent.GetChild(focusedIndex)
            if itemNode <> invalid and itemNode.id.toStr() = videoId
                if m.previewPoster <> invalid
                    m.previewPoster.uri = localPath
                end if
            end if
        end if
    end if
end sub

sub onDeepLinkInput()
    deeplink = m.inputTask.inputData
    if deeplink = invalid then return
    if deeplink.id = "" or deeplink.id = invalid then return

    print "MainScene: Deep link received for contentID="; deeplink.id

    if m.videoContent <> invalid
        for i = 0 to m.videoContent.GetChildCount() - 1
            childNode = m.videoContent.GetChild(i)
            if childNode <> invalid and childNode.id.toStr() = deeplink.id.toStr()
                print "MainScene: Deep link match found, playing video at index "; i
                playVideo(i)
                return
            end if
        end for
    end if

    print "MainScene: Deep link contentID not found: "; deeplink.id
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    handled = false
    if press then
        if m.videoPlayer <> invalid and m.videoPlayer.visible = true
            if key = "back"
                print "Closing video player..."
                m.videoPlayer.control = "stop"
                m.videoPlayer.visible = false
                m.videoList.setFocus(true)
                handled = true
            end if
        else if key = "options"
            showOptionsMenu()
            handled = true
        end if
    end if
    return handled
end function

sub deleteVideoFromServer(itemIndex as Integer, videoId as String)
    m.apiTask.actionRequest = { type: "delete", videoId: videoId }
    removeVideoFromList(itemIndex)
end sub

sub deleteAndIgnoreVideoFromServer(itemIndex as Integer, videoId as String)
    m.apiTask.actionRequest = { type: "ignore", videoId: videoId }
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
    if not m.showPostPlayDialogSetting then
        m.videoList.setFocus(true)
        return
    end if

    scene = m.top.getScene()
    scene.dialog = invalid

    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.title = "Video Finished"
    dialog.message = ["Delete and Ignore this video?"]
    dialog.buttons = ["Delete & Ignore", "Keep Video"]

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

' ==================== Settings ====================

sub loadSettings()
    sec = CreateObject("roRegistrySection", "AppSettings")

    if sec.Exists("serverURL")
        m.serverURL = sec.Read("serverURL")
    else
        m.serverURL = ""
    end if

    if sec.Exists("showPostPlayDialog")
        m.showPostPlayDialogSetting = sec.Read("showPostPlayDialog") = "true"
    else
        m.showPostPlayDialogSetting = false
        sec.Write("showPostPlayDialog", "true")
        sec.Flush()
    end if

    print "MainScene: Loaded settings - serverURL='"; m.serverURL; "' showPostPlayDialog="; m.showPostPlayDialogSetting
end sub

sub saveSettings()
    sec = CreateObject("roRegistrySection", "AppSettings")
    sec.Write("serverURL", m.serverURL)
    sec.Write("showPostPlayDialog", m.showPostPlayDialogSetting.toStr())
    sec.Flush()
    print "MainScene: Saved settings - serverURL="; m.serverURL; " showPostPlayDialog="; m.showPostPlayDialogSetting
end sub

sub showOptionsMenu()
    scene = m.top.getScene()
    scene.dialog = invalid

    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.title = "Pinchflat"
    dialog.message = [m.serverURL]
    dialog.buttons = ["Play", "Delete File", "Delete & Ignore", "Settings", "Cancel"]

    if m.videoList <> invalid and m.videoContent <> invalid
        focusedIndex = m.videoList.itemFocused
        if focusedIndex >= 0
            itemNode = m.videoContent.GetChild(focusedIndex)
            if itemNode <> invalid
                dialog.addFields({
                    itemIndex: focusedIndex
                    videoId: itemNode.id.toStr()
                    videoTitle: itemNode.title
                })
            end if
        end if
    end if

    dialog.observeField("buttonSelected", "onMenuSelected")
    scene.dialog = dialog
end sub

sub onMenuSelected()
    scene = m.top.getScene()
    dialog = scene.dialog
    if dialog = invalid then return

    buttonIndex = dialog.buttonSelected
    itemIndex = dialog.itemIndex
    videoId = dialog.videoId

    scene.dialog = invalid

    if buttonIndex = 0
        if itemIndex <> invalid then playVideo(itemIndex)
    else if buttonIndex = 1
        if itemIndex <> invalid and videoId <> invalid then deleteVideoFromServer(itemIndex, videoId)
    else if buttonIndex = 2
        if itemIndex <> invalid and videoId <> invalid then deleteAndIgnoreVideoFromServer(itemIndex, videoId)
    else if buttonIndex = 3
        showSettingsDialog()
    end if
end sub

sub showSettingsDialog()
    scene = m.top.getScene()
    scene.dialog = invalid

    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.title = "Settings"

    postPlayStatus = "ON"
    if not m.showPostPlayDialogSetting then postPlayStatus = "OFF"

    dialog.message = ["Server: " + m.serverURL, "Video Finished Dialog: " + postPlayStatus]
    dialog.buttons = ["Change Server Address", "Toggle Video Finished Dialog", "Close"]

    dialog.observeField("buttonSelected", "onSettingsSelected")
    scene.dialog = dialog
end sub

sub onSettingsSelected()
    scene = m.top.getScene()
    dialog = scene.dialog
    if dialog = invalid then return

    buttonIndex = dialog.buttonSelected
    scene.dialog = invalid

    if buttonIndex = 0
        showServerInputDialog()
    else if buttonIndex = 1
        togglePostPlayDialog()
    end if
end sub

sub showServerInputDialog()
    scene = m.top.getScene()
    scene.dialog = invalid

    m.top.signalBeacon("AppDialogInitiate")

    dialog = CreateObject("roSGNode", "StandardKeyboardDialog")
    dialog.title = "Server Address (IP:port or hostname.example.com)"
    dialog.text = m.serverURL
    dialog.keyboardDomain = "alphanumeric"
    dialog.buttons = ["Save", "Cancel"]

    dialog.observeField("buttonSelected", "onServerInputSelected")
    scene.dialog = dialog
end sub

sub onServerInputSelected()
    scene = m.top.getScene()
    dialog = scene.dialog
    if dialog = invalid then return

    buttonIndex = dialog.buttonSelected
    scene.dialog = invalid

    m.top.signalBeacon("AppDialogComplete")

    if buttonIndex = 0
        newURL = dialog.text
        newURL = newURL.Trim()

        ' Strip trailing slash
        if Right(newURL, 1) = "/"
            newURL = Left(newURL, Len(newURL) - 1)
        end if

        if newURL <> ""
            m.serverURL = newURL
            saveSettings()

            if m.feedLoaded
                restartFeed()
            else
                loadFeed()
            end if
        end if

        showSettingsDialog()
    else
        ' Cancel pressed - if no URL set yet, prompt again
        if m.serverURL = ""
            showServerInputDialog()
        else
            showSettingsDialog()
        end if
    end if
end sub

sub togglePostPlayDialog()
    m.showPostPlayDialogSetting = not m.showPostPlayDialogSetting
    saveSettings()
    showSettingsDialog()
end sub

sub restartFeed()
    print "MainScene: Restarting feed with serverURL="; m.serverURL
    m.thumbnailCache = {}
    m.apiTask = CreateObject("roSGNode", "APITask")
    m.apiTask.observeField("content", "onFeedLoaded")
    m.apiTask.observeField("thumbnailResult", "onThumbnailLoaded")
    m.apiTask.observeField("errorMessage", "onAPIError")
    m.apiTask.serverURL = m.serverURL
    m.apiTask.control = "RUN"
end sub

sub onAPIError()
    errorMsg = m.apiTask.errorMessage
    if errorMsg = "" or errorMsg = invalid then return

    scene = m.top.getScene()
    scene.dialog = invalid

    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.title = "Connection Error"
    dialog.message = [errorMsg]
    dialog.buttons = ["Retry", "Change URL"]

    dialog.observeField("buttonSelected", "onAPIErrorAction")
    scene.dialog = dialog
end sub

sub onAPIErrorAction()
    scene = m.top.getScene()
    dialog = scene.dialog
    if dialog = invalid then return

    buttonIndex = dialog.buttonSelected
    scene.dialog = invalid

    if buttonIndex = 0
        loadFeed()
    else if buttonIndex = 1
        showServerInputDialog()
    end if
end sub
