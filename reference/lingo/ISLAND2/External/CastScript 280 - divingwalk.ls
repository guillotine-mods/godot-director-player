on mouseUp
  global egozh, egozv, nextroomdata
  if sprite(38).visible = 1 then
    nextroomdata = "000"
    egozv = the mouseV
    egozh = the mouseH
    walkonby2()
  end if
end
