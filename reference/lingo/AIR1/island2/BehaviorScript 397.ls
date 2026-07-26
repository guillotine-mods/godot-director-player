on exitFrame
  global monk, monk2
  monk2 = 0
  sprite(27).visible = 0
  sprite(28).visible = 0
  sprite(29).visible = 0
  x = random(3)
  sprite(26 + x).visible = 1
  case x of
    1:
      monk = "plc1"
    2:
      monk = "plc2"
    3:
      monk = "plc3"
  end case
  set the cursor of sprite 6 to [member("magni1").memberNum, member("magni2").memberNum]
end
