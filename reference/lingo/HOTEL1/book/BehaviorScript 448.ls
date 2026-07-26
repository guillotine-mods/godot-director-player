on exitFrame
  global egozv, egozh, newsyz, nextroomdata
  go("verandaz", "day1.dir")
  peoplefunk()
  puppetSprite(30, 1)
  sprite(30).visible = 1
  nextroomdata = "000"
  if the movieName = "day1.dxr" then
    cursorfunk()
    displayobject()
  end if
end
