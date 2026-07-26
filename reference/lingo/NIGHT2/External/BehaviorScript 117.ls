on exitFrame
  global egozh, egozv, newsyz, syz, nextroomdata
  syz = 8
  newsyz = 8
  egozh = 351
  egozv = 389
  set the locH of sprite 30 to 351
  set the locV of sprite 30 to 389
  put "fort" into item 1 of nextroomdata
  go(item 1 of nextroomdata)
  set the visible of sprite 30 to 1
  nextroomdata = "000"
end
