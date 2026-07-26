on exitFrame
  global map, nextroomdata, egozv, egozh, newsyz, syz
  if map = "cave" then
    go("entercave")
    newsyz = 5
    syz = 5
    egozv = 308
    egozh = 207
    put "cave" into item 1 of nextroomdata
  end if
end
