# 📘 Literal Translation: Epson QC-11 Article (ASCII Magazine, August 1985)

> 📄 Original Source: ASCII Magazine, Vol. 9, No. 8  
> 🗓️ August 1985  
> 📂 Article Pages: 170–171  
> 🖨️ Scanned PDF: `QC11-ARTICLE_.pdf`  

---

## QC-11  
### 日本のオフィス環境に合ったコンパクト設計  
### OSをROMで搭載したユニークなマシン  
**QC-11: A uniquely compact machine designed for Japanese office environments, featuring ROM-based OS**

---

## エプソン

今回紹介するQC-11は、内蔵のROMにMS-DOS Ver 2.11を搭載した、言わば「SWITCH ON OS」ともいえるユニークなマシンである。  
**This time we introduce the QC-11, a unique machine equipped with MS-DOS Ver. 2.11 stored in internal ROM—a so-called “Switch-On OS.”**

従来の国産機のような、BASICをROMで搭載しているマシンとは異なり、このマシンは本格的なOS時代を実感させてくれる。  
**Unlike Japanese machines that came with BASIC in ROM, this unit gives users a real sense of the operating system era.**

基本的にはビジネスユースのマシンという印象を受けたが、ユーザーの意識次第で多様な応用が考え得る。  
**Although it gives the impression of being a business machine, a wide variety of applications can be considered depending on user intent.**

6月号のASCII EXPRESSに引き続き、今回はその全貌を明らかにしていこう。  
**Following the June issue’s ASCII EXPRESS article, this time we aim to reveal the full picture.**

---

## ディスケットを入れずに立ち上がるMS-DOS  
**MS-DOS boots without inserting a diskette**

QC-11の主な仕様については、表1を参照してほしい。  
**Refer to Table 1 for the main specifications of the QC-11.**

本体のスイッチを入れると、RAMとキーボードのチェックを行った後ディスケットを入れなくてもMS-DOSが立ち上がる。  
**When the power switch is turned on, RAM and keyboard are checked, and MS-DOS boots even without inserting a diskette.**

これは、システムはおろかコマンドインタプリタであるcommand.comまでがROMに入ってしまっているためである。  
**This is because not only the system but also the command interpreter command.com is stored in ROM.**

そのため、ルートディレクトリにコマンドインタプリタがなかったり、そのバージョンが違っていて苦労することがなくなる。  
**As a result, there is no need to struggle with missing or mismatched command interpreters in the root directory.**

OSをROMで搭載していることのもうひとつの利点に、ディスクのスペースを節約できるということがある。  
**Another benefit of storing the OS in ROM is that it saves disk space.**

---

## 高速な連文節変換を可能にした漢字辞書ROM  
**Kanji Dictionary ROM enables high-speed phrase conversion**

標準装備の一般用漢字辞書ROMの他に、オプションとして専門用語の漢字辞書ROMを装着することもできる。  
**In addition to the standard general-purpose kanji dictionary ROM, an optional technical terms dictionary ROM can be installed.**

MS-DOSに用意されている各種デバイスドライバ（文節変換、マウスドライバなど）をいちいち全てのディスケットに入れておく必要がなくなるわけだ。  
**There’s no need to include all MS-DOS drivers (e.g., phrase conversion, mouse drivers) on every disk.**

ただ、今後のMS-DOSのバージョンアップに対してはどのように対処するのだろうか。  
**But how will version upgrades to MS-DOS be handled in the future?**

一般のユーザーにROMの交換を行わせるのはチップの足が曲がったり静電気破損が起こったりする可能性があり不安が残る。  
**Having general users replace ROMs is risky, as bent pins or electrostatic damage may occur.**

---

## OSレベルでの連文節変換をサポート  
**Supports multi-phrase kanji conversion at the OS level**

このマシンに搭載されたMS-DOSは日本語対応のもので、かな漢字の連文節変換の機能をサポートしている。  
**The MS-DOS built into this machine supports Japanese language processing, including kana-kanji multi-phrase conversion.**

変換に使用する漢字辞書をROMで内蔵しているため、変換のたびにディスクをアクセスする必要がなく高速な変換が可能になる。  
**Since the dictionary is stored in ROM, there's no need for disk access during conversion, enabling high-speed operation.**

スプレッドシートやデータベースなどのアプリケーションの中から漢字を利用することも容易である。  
**It is also easy to use kanji within applications like spreadsheets or databases.**

変換方式では連文節変換の他に、読み、部首、画数、JIS区点入力などがある。  
**Other conversion methods include reading, radical, stroke count, and JIS code point input.**

(…continues through the rest of the article…)

---

📄 Original article: [`QC11-ARTICLE_.pdf`](QC11-ARTICLE_.pdf)  
📝 Source: ASCII Magazine (Japan), August 1985  
