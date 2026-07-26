on mouseUp
  global egozh, egozv, whatodo, nextroomdata, ifmovie, globalday, soundspath
  if globalday <> 1 then
    nextroomdata = "000"
    if (egozv <> 308) and (egozh <> 207) then
      ifmovie = "1,shore2updeck"
      egozv = 308
      egozh = 207
      walkonby()
    else
      if whatodo = "stand" then
        sprite(30).visible = 0
        go("shore2updeck")
      end if
    end if
  else
    sound playFile 1, soundspath & "nodecks.aif"
  end if
end
