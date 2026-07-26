on exitFrame
  global egozh, egozv, nextroomdata
  nextroomdata = "hall1,274,210"
  go("hall1")
  egozv = 210
  egozh = 274
  puppetSprite(30, 1)
  set the locH of sprite 30 to egozh
  set the locV of sprite 30 to egozv
  updateStage()
end
