on exitFrame
  global globalnight
  if item 1 of globalnight = "0" then
    sprite(17).visible = 0
  else
    put 1 into item 1 of globalnight
    sprite(17).visible = 1
  end if
end
