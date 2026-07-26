on exitFrame
  global SaveNames, globalday, Whichins, Whichins2, saveB, saveD, saveC, saveE, saveF, saveG, saveH, savei, egozh, egozv, syz, DorN, savepath
  saveB = field("clickoncharacter", "master")
  saveG = field("jokefield", "master")
  saveF = field("points", "master")
  saveE = field("plane", "master")
  saveD = field("shellfield", "master")
  saveC = field("objectsfield", "master")
  saveH = field("Dprocess", "master")
  savei = egozh & "," & egozv & "," & syz
  tell the stage
    DorN = the movieName
  end tell
  tell the stage
    sound stop 2
  end tell
  go("fillnames", savepath & "hezsave.dir")
end
