on mouseUp
  global egozh, egozv, whatodo, nextroomdata, ifmovie
  nextroomdata = "000"
  if (egozv <> 177) and (egozh <> 353) then
    ifmovie = "0,0"
    egozv = 177
    egozh = 353
    walkonby()
  else
    if whatodo = "stand" then
      go(1, "pptshow.dxr")
    end if
  end if
end
