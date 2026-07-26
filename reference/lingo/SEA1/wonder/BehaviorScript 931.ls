on exitFrame
  global wreck
  puppetSprite(16, 0)
  set the visible of sprite 20 to 1
  put 1 + value(item 9 of wreck) into item 9 of wreck
  if value(item 9 of wreck) > 5 then
    go("monsspk")
  else
    go("throw")
  end if
end
