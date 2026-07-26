on exitFrame
  global syz, egozv, egozh, newsyz, nextroomdata
  newsyz = 7
  syz = 7
  set the volume of sound 2 to 255
  go(1, "day1.dir")
  puppetSprite(30, 1)
  set the memberNum of sprite 30 to the number of member "standleft7"
  updateStage()
  sprite(30).visible = 1
  displayobject()
  cursorfunk()
end
