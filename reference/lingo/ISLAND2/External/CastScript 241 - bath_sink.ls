on mouseUp
  global egozh, egozv, whatodo, whereami, nextroomdata, newsyz, ifmovie, sink
  if sink = 1 then
    if whereami = label("bath") then
      ifmovie = "1,sinkscrm"
      newsyz = 7
      y = 388
      x = 359
      y2 = 315
      x2 = 200
    end if
    egozv = y
    egozh = x
    put x2 into item 2 of nextroomdata
    put y2 into item 3 of nextroomdata
    put "rooma" into item 1 of nextroomdata
    walkonby()
  else
    searchfunk()
  end if
end
