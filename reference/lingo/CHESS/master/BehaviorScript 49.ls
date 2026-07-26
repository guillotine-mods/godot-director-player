on exitFrame
  repeat with i = 7 to 49
    set the visible of sprite i to 0
  end repeat
  set the cursor of sprite 4 to [member("cc1").memberNum, member("cc1b").memberNum]
  set the cursor of sprite 5 to [member("cc2").memberNum, member("cc2b").memberNum]
  set the cursor of sprite 6 to [member("cc3").memberNum, member("cc3b").memberNum]
end
