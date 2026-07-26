on mouseUp
  global egozh, egozv, nextroomdata
  if (sprite(35).visible = 0) and (sprite(33).visible = 0) then
    nextroomdata = "000"
    egozv = the mouseV
    egozh = the mouseH
    walkonby3()
  end if
end
