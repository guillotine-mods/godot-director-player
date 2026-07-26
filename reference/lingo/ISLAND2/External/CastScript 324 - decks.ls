on mouseUp
  global egozh, egozv, whatodo, nextroomdata, ifmovie
  nextroomdata = "000"
  if (egozv <> 319) and (egozh <> 342) then
    ifmovie = "0,0"
    egozv = 319
    egozh = 342
    walkonby()
  else
    if whatodo = "stand" then
      go(1, "chess.dxr")
    end if
  end if
end
