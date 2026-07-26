on exitFrame
  global SaveNames, globalday, Whichins2, Whichins, saveD, saveC, saveF, saveE, savepath, savei, egozh, egozv, syz, saveG, saveH, saveB
  saveF = field("points", "master")
  saveE = field("plane", "master")
  saveD = field("shellfield", "master")
  saveC = field("objectsfield", "master")
  savei = egozh & "," & egozv & "," & syz
  saveG = field("jokefield", "master")
  saveH = field("Dprocess", "master")
  saveB = field("clickoncharacter", "master")
  go("fillnames2", savepath & "hezsave.dir")
end
