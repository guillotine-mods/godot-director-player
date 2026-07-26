on mouseUp
  global egozh, egozv, nextroomdata, whatodo, soundspath
  nextroomdata = "000"
  if (egozv <> 276) and (egozh <> 145) then
    egozv = 276
    egozh = 145
    walkonby()
  else
    if whatodo = "stand" then
      sound playFile 1, soundspath & "pgold" & random(5) & ".aif"
    end if
  end if
end
