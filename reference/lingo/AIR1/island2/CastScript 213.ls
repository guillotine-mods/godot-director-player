on mouseUp
  global egozh, egozv, whatodo, nextroomdata
  nextroomdata = "000"
  if (egozv <> 328) or (egozh <> 244) then
    egozv = 328
    egozh = 244
    walkonby()
  else
    if whatodo = "stand" then
      set the visible of sprite 30 to 0
      go("toolsfall")
    end if
  end if
end
