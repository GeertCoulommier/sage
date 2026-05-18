<#
    Colour semantics:
      Primary   — titles, active panel borders, highlights
      Accent    — sub-headers, secondary emphasis
      Pass      — passed tests, high scores
      Fail      — failed tests, low scores
      Warn      — Warn scores, warnings
      Muted     — borders, inactive items, hints
      Header    — ASCII art logo, box borders
#>

$Themes = @(
    @{ Name = '1. Cyberpunk Neon'; Primary = 'grey85'; Accent = 'black on springgreen3'; Header = 'cyan1'; Sub = 'magenta1'; Pass = 'springgreen3'; Warn = 'gold1'; Fail = 'deeppink2'; Muted = 'grey42' }
    @{ Name = '2. Synthwave 80s'; Primary = 'grey89'; Accent = 'white on darkviolet'; Header = 'orchid1'; Sub = 'lightcyan1'; Pass = 'green1'; Warn = 'orange1'; Fail = 'red1'; Muted = 'grey39' }
    @{ Name = '3. Matrix Terminal'; Primary = 'green3'; Accent = 'black on green1'; Header = 'green1'; Sub = 'darkgreen'; Pass = 'green1'; Warn = 'green3'; Fail = 'darkgreen'; Muted = 'grey30' }
    @{ Name = '4. Ocean Breeze'; Primary = 'grey84'; Accent = 'black on lightcyan1'; Header = 'deepskyblue1'; Sub = 'aquamarine1_1'; Pass = 'cyan1'; Warn = 'lightgoldenrod1'; Fail = 'darkorange'; Muted = 'grey50' }
    @{ Name = '5. Forest Timber'; Primary = 'grey78'; Accent = 'white on darkolivegreen3'; Header = 'khaki1'; Sub = 'darkseagreen2_1'; Pass = 'darkseagreen1'; Warn = 'lightgoldenrod2_1'; Fail = 'lightpink3'; Muted = 'grey35' }
    @{ Name = '6. Dracula Dark'; Primary = 'grey93'; Accent = 'black on plum1'; Header = 'mediumpurple1'; Sub = 'cyan2'; Pass = 'green3_1'; Warn = 'gold3_1'; Fail = 'deeppink1'; Muted = 'grey46' }
    @{ Name = '7. Solarized Dark'; Primary = 'grey69'; Accent = 'black on darkcyan'; Header = 'yellow3'; Sub = 'lightskyblue3'; Pass = 'green3'; Warn = 'darkorange'; Fail = 'red3'; Muted = 'grey39' }
    @{ Name = '8. Nordic Frost'; Primary = 'grey82'; Accent = 'black on lightsteelblue'; Header = 'cadetblue_1'; Sub = 'lightskyblue1'; Pass = 'darkseagreen1'; Warn = 'lightsalmon1'; Fail = 'darkorange'; Muted = 'grey54' }
    @{ Name = '9. Vintage Amber'; Primary = 'orange3'; Accent = 'black on gold1'; Header = 'gold1'; Sub = 'orange4_1'; Pass = 'gold1'; Warn = 'darkorange3'; Fail = 'darkorange'; Muted = 'grey27' }
    @{ Name = '10. Pastel Soft'; Primary = 'grey85'; Accent = 'white on lightpink1'; Header = 'plum1'; Sub = 'lightcyan1'; Pass = 'palegreen1_1'; Warn = 'khaki1'; Fail = 'lightpink1'; Muted = 'grey58' }
)

$Themes += @(
    # 11. Catppuccin Mocha - Extreem populair vanwege de zachte pastelkleuren op een donker canvas
    @{ Name = '11. Catppuccin Mocha'; Primary = 'grey85'; Accent = 'black on skyblue1'; Header = 'plum1'; Sub = 'lightcyan1'; Pass = 'green3'; Warn = 'gold1'; Fail = 'orange1'; Muted = 'grey42' }
    
    # 12. Tokyo Night - Geïnspireerd op de neonlichten van het nachtelijke Tokio
    @{ Name = '12. Tokyo Night'; Primary = 'grey82'; Accent = 'black on darkturquoise'; Header = 'mediumpurple1'; Sub = 'cyan1'; Pass = 'springgreen3'; Warn = 'orange1'; Fail = 'red1'; Muted = 'grey35' }
    
    # 13. Nord - De klassieke ijskoude, arctische sfeer met gedempte pasteltinten
    @{ Name = '13. Nord Ice'; Primary = 'grey89'; Accent = 'white on steelblue'; Header = 'cadetblue_1'; Sub = 'cyan2'; Pass = 'darkseagreen1'; Warn = 'khaki1'; Fail = 'lightpink1'; Muted = 'grey54' }
    
    # 14. Gruvbox Dark - Warme, retro pastelkleuren die erg zacht zijn voor de ogen
    @{ Name = '14. Gruvbox Dark'; Primary = 'gold3_1'; Accent = 'black on yellow3'; Header = 'gold1'; Sub = 'darkorange'; Pass = 'green3'; Warn = 'gold3_1'; Fail = 'red3'; Muted = 'grey30' }
    
    # 15. Monokai Pro - Het legendarische contrastrijke thema, gefinetuned voor moderne UI
    @{ Name = '15. Monokai Pro'; Primary = 'grey93'; Accent = 'black on yellow1'; Header = 'mediumspringgreen'; Sub = 'cyan1'; Pass = 'green1'; Warn = 'orange1'; Fail = 'deeppink1'; Muted = 'grey42' }
    
    # 16. One Dark Pro - De standaard van Atom en VS Code, zeer gebalanceerd
    @{ Name = '16. One Dark Pro'; Primary = 'grey85'; Accent = 'white on dodgerblue2'; Header = 'indianred1'; Sub = 'lightgoldenrod2_1'; Pass = 'green3'; Warn = 'gold3_1'; Fail = 'red3'; Muted = 'grey39' }
    
    # 17. Night Owl - Specifiek ontworpen voor nachtelijke codeersessies (weinig blauw licht)
    @{ Name = '17. Night Owl'; Primary = 'lightgoldenrod2_1'; Accent = 'black on lightskyblue1'; Header = 'mediumorchid1'; Sub = 'aquamarine1_1'; Pass = 'green1'; Warn = 'gold1'; Fail = 'magenta1'; Muted = 'grey35' }
    
    # 18. Ayu Mirage - Een prachtig gebalanceerd tussenstation tussen fel en donker
    @{ Name = '18. Ayu Mirage'; Primary = 'grey82'; Accent = 'black on orange1'; Header = 'lightgoldenrod1'; Sub = 'aquamarine1_1'; Pass = 'springgreen3'; Warn = 'gold1'; Fail = 'darkorange'; Muted = 'grey46' }
    
    # 19. Rose Pine - De populaire trendset met een unieke 'dusky' esthetiek
    @{ Name = '19. Rose Pine'; Primary = 'grey89'; Accent = 'black on pink1'; Header = 'lightsalmon1'; Sub = 'lightskyblue1'; Pass = 'darkseagreen1'; Warn = 'gold1'; Fail = 'lightpink1'; Muted = 'grey39' }
    
    # 20. GitHub Dark - De vertrouwde donkere omgeving van het grootste codeplatform
    @{ Name = '20. GitHub Dark'; Primary = 'grey85'; Accent = 'white on steelblue3'; Header = 'lightskyblue1'; Sub = 'aquamarine1_1'; Pass = 'green1'; Warn = 'gold1'; Fail = 'red1'; Muted = 'grey35' }
)

$Themes += @(
    # 21. Cloud Dancer (Trend) - De zachte witte rust gecombineerd met diepe aardetinten
    @{ Name = '21. Cloud Dancer'; Primary = 'grey93'; Accent = 'black on silver'; Header = 'grey100'; Sub = 'lightskyblue1'; Pass = 'aquamarine1_1'; Warn = 'khaki1'; Fail = 'lightpink1'; Muted = 'grey50' }
    
    # 22. Mocha Mousse (Trend) - Warme cacao en koffietinten voor een rijke, organische sfeer
    @{ Name = '22. Mocha Mousse'; Primary = 'wheat1'; Accent = 'black on wheat4'; Header = 'darkorange3'; Sub = 'sandybrown'; Pass = 'darkseagreen2_1'; Warn = 'gold3_1'; Fail = 'darkorange'; Muted = 'grey35' }
    
    # 23. Viva Magenta - Energiek, krachtig en gedurfd (gebaseerd op het befaamde Pantone jaar)
    @{ Name = '23. Viva Magenta'; Primary = 'grey89'; Accent = 'white on deeppink2'; Header = 'deeppink2'; Sub = 'plum1'; Pass = 'springgreen3'; Warn = 'gold1'; Fail = 'red1'; Muted = 'grey42' }
    
    # 24. New Age Pastels (Dualities) - Moderne, dromerige pastels voor een lichte focus
    @{ Name = '24. New Age Pastel'; Primary = 'grey85'; Accent = 'white on lightcyan1'; Header = 'violet'; Sub = 'skyblue1'; Pass = 'palegreen1_1'; Warn = 'khaki1'; Fail = 'lightpink1'; Muted = 'grey58' }
    
    # 25. Earthy Boho - Geïnspireerd op organische materialen, klei, linnen en rotan
    @{ Name = '25. Earthy Boho'; Primary = 'navajowhite1'; Accent = 'black on darkorange3'; Header = 'orange3'; Sub = 'tan'; Pass = 'darkseagreen2_1'; Warn = 'gold3_1'; Fail = 'darkorange'; Muted = 'grey27' }
    
    # 26. Forest Velvet - De luxe sfeer van diep bosgroen gecombineerd met goud en marmer
    @{ Name = '26. Forest Velvet'; Primary = 'grey84'; Accent = 'white on darkgreen'; Header = 'darkgoldenrod'; Sub = 'darkseagreen2_1'; Pass = 'springgreen3'; Warn = 'orange3'; Fail = 'darkorange'; Muted = 'grey39' }
    
    # 27. Quiet Luxury - Subtiele contrasten, kasjmier grijs en rustige premium accenten
    @{ Name = '27. Quiet Luxury'; Primary = 'grey89'; Accent = 'white on cadetblue_1'; Header = 'silver'; Sub = 'lightcyan1'; Pass = 'darkseagreen1'; Warn = 'khaki1'; Fail = 'lightpink1'; Muted = 'grey50' }
    
    # 28. Mid-Century Modern - Teak houtkleuren gecombineerd met mosterdgeel en avocadogroen
    @{ Name = '28. Mid-Century Mod'; Primary = 'tan'; Accent = 'black on gold3_1'; Header = 'darkorange'; Sub = 'khaki1'; Pass = 'darkseagreen3'; Warn = 'orange4_1'; Fail = 'darkorange'; Muted = 'grey35' }
    
    # 29. Desert Sunset - Warme terracotta tinten die overlopen in paarse schaduwen
    @{ Name = '29. Desert Sunset'; Primary = 'lightpink3'; Accent = 'white on darkorange3'; Header = 'lightgoldenrod1'; Sub = 'salmon1'; Pass = 'khaki1'; Warn = 'orange3'; Fail = 'darkorange'; Muted = 'grey30' }
    
    # 30. Scandinavian Minimal - Koel marmer met strakke lijnen en zachte houten details
    @{ Name = '30. Scandi Minimal'; Primary = 'grey82'; Accent = 'black on skyblue1'; Header = 'lightcyan1'; Sub = 'silver'; Pass = 'palegreen1_1'; Warn = 'lightgoldenrod2_1'; Fail = 'lightpink1'; Muted = 'grey54' }
)