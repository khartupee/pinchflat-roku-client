sub init()
    m.top.functionName = "listenInput"
end sub

sub listenInput()
    port = CreateObject("roMessagePort")
    inputObject = CreateObject("roInput")
    inputObject.SetMessagePort(port)

    while true
        msg = port.WaitMessage(500)
        if type(msg) = "roInputEvent"
            if msg.IsInput()
                inputData = msg.GetInfo()
                if inputData.DoesExist("mediaType") and inputData.DoesExist("contentID")
                    deeplink = {
                        id: inputData.contentID
                        type: inputData.mediaType
                    }
                    m.top.inputData = deeplink
                end if
            end if
        end if
    end while
end sub
