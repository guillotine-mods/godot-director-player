on exitFrame
  global egozv, egozh, newsyz, nextroomdata
  newsyz = 6
  y = 227
  x = 346
  y2 = 227
  x2 = 346
  egozv = y
  egozh = x
  put x2 into item 2 of nextroomdata
  put y2 into item 3 of nextroomdata
  put "rooma" into item 1 of nextroomdata
  go(item 1 of nextroomdata)
  sprite(30).visible = 1
  whatodoeveryframe()
  go("rooma")
end
