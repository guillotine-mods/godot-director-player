on exitFrame
  global map, nextroomdata, egozv, egozh, newsyz, syz
  if map = "wreck" then
    go("wreck")
    newsyz = 5
    syz = 5
    egozv = 308
    egozh = 207
    put "wreck" into item 1 of nextroomdata
  end if
end
