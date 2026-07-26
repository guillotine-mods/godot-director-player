on mouseUp
  global egozh, egozv, nextroomdata, whatodo, soundspath
  nextroomdata = "000"
  if (egozv <> 370) and (egozh <> 520) then
    egozv = 370
    egozh = 520
    sound playFile 1, soundspath & "plytnis.aif"
    walkonby()
  else
    if whatodo = "stand" then
      go(1, the moviePath & "tennis.dir")
    end if
  end if
end
