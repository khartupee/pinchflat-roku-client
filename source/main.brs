sub Main()
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)
    screen.CreateScene("MainScene")
    screen.Show()

    while true
        msg = port.WaitMessage(0)
        if msg <> invalid
            if type(msg) = "roSGScreenEvent"
                if msg.IsScreenClosed() then exit while
            end if
        end if
    end while
end sub
