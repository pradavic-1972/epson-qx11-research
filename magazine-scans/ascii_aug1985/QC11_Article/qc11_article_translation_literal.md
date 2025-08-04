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

---

## キーボードもディスプレイもコンパクト設計  
**Compact design for both keyboard and display**

このマシンの最も大きな特徴はコンパクトさである。  
**The greatest feature of this machine is its compactness.**

(…remainder of translation continues as in previous cell…)

📄 Original article: [`QC11-ARTICLE_.pdf`](QC11-ARTICLE_.pdf)  
📝 Source: ASCII Magazine (Japan), August 1985  


---

## QC-11の性能を引き出すユーティリティ  
**Utilities that bring out the QC-11’s performance**

標準で付属してくるソフトウェアには日本語GW-BASICとMS-DOSのユーティリティがある。  
**The standard software package includes Japanese GW-BASIC and MS-DOS utilities.**

ユーティリティの中のコンフィギュレーションプログラムによって、システム起動時の各種条件が設定でき、その内容はCMOSのバックアップメモリに保存される。  
**With the configuration utility, various system startup parameters can be set and stored in backup CMOS memory.**

その中にユーザーエリアの一部をRAMディスクとして使用するという機能がある。  
**One such function allows part of the user area to be used as a RAM disk.**

これはアセンブラやコンパイルを高速に行うのに有用に思われるが、最大512KbytesのRAMしか実装できないことを考えると本格的なプログラム開発には向いていない。  
**While useful for speeding up assembly or compilation, the system’s RAM limit (512KB max) makes it unsuitable for serious development.**

むしろ、これは頻繁にディスクアクセスをするようなデータベースなどのアプリケーションプログラムを高速に実行するためのものであると考えたほうがよいだろう。  
**Instead, it’s better understood as a feature for accelerating disk-heavy applications like databases.**

---

## ハンドヘルドで培われた通信技術  
**Communication features inherited from handheld development**

また、ハンドヘルドで培われた通信技術は本機にも生きている。  
**The communication technologies developed through Epson’s handhelds are applied to this system as well.**

TERMやFLINKというユーティリティと標準装備のRS-232Cインターフェースによって、本機はファイルの送受信も可能な日本語ターミナルとなる。  
**With TERM and FLINK utilities and a built-in RS-232C interface, the QC-11 functions as a Japanese terminal capable of file transfer.**

---

## さて、その使い心地は？  
**And how does it feel to use?**

本体内蔵のディスクドライブは自社開発のもので、ディスクの出し入れは極めてスムーズ、作動音も静かだ。  
**The built-in disk drive, developed in-house, offers very smooth disk insertion/ejection and operates quietly.**

アクセス速度は8インチや5インチ2HDなどを使っている人にはいささか遅く感じられるかもしれないが、5インチ2Dや2DDのものよりは良いという印象を受ける。  
**While users of 8" or 5" 2HD drives may find it somewhat slow, it feels faster than 5" 2D/2DD units.**

キーボードに関しては、タッチは軽くクリックの感じも軽快だ。  
**The keyboard has a light touch and a crisp click feel.**

ただ、日本語処理関連のキーがたくさん付いているので、慣れるまではそれらの操作に戸惑うかもしれない。  
**However, the many keys for Japanese input may confuse users until they become accustomed to them.**

ただ、画面の表示速度に関しては決して速いとはいえない。  
**That said, the screen display speed is not particularly fast.**

特にGW-BASIC上の画面スクロールなどは、BASICが遅いのも手伝って我慢できる限界ともいえるスピードで表示される。  
**Scrolling in GW-BASIC is notably slow, compounded by BASIC’s own slowness—it approaches the limits of patience.**

これは各キャラクタをビットパターンに展開して表示しているためであろう。  
**This is likely due to rendering each character as a bitmap.**

この特集の末尾にあるベンチマークテストの結果を見てもらえば分かると思うが、画面表示関係を除けば他の16ビットマシンと比べても速度的にはそれほど遅くはない。  
**Benchmark results in the end of the article confirm that apart from display performance, the QC-11 holds up well against other 16-bit machines.**

しかし、画面表示が遅いと、それだけで「遅い」という印象を受けてしまうことは否めない。  
**Still, slow screen rendering alone strongly contributes to the impression of a slow machine.**

---

# (Final part with hardware analysis and summary will follow next)



---

## CPUとそれを取り巻くカスタムIC  
**The CPU and its surrounding custom ICs**

CPUには8088-2（8086のデータバス8bitバージョン、クロック周波数4.92MHz）を採用している。  
**The CPU used is the 8088-2, an 8-bit data bus version of the 8086, operating at 4.92MHz.**

巷の関心が80186から80286に向かおうとしている今、なぜこのようなCPUを使用するのだろうか。  
**With public interest shifting from the 80186 to the 80286, one might ask: why use this CPU?**

理由として考えられるのは、コストパフォーマンスを追求した結果ということだ。  
**The likely reason is the pursuit of cost-performance balance.**

確かに一般のオフィスで必要な表計算やデータの検索、文書の作成などの作業をこなすには8088でも十分。  
**For standard office tasks like spreadsheets, data lookups, and word processing, the 8088 is sufficient.**

コストやサイズとのバランスも考えて、あえて高性能なCPUを使わなくても間に合うことはできる。  
**Given cost and size trade-offs, there's no need to push for a higher-performance CPU.**

しかし、日本語処理を効率よく行うには、8088では明らかに力不足である。  
**However, for efficient Japanese language processing, the 8088 is clearly underpowered.**

ご存知のように漢字は16bitで表現されるため、それを2度に分けて処理するのはあまりにも冗長である。  
**As you may know, kanji are expressed in 16-bit code, and processing them in two parts is overly inefficient.**

この8088の周囲は2つのペリフェラルコントローラ、FDC、メモリコントローラ、ビデオコントローラと5つのカスタムICが固めており、コンパクト化に貢献している。  
**Around the 8088 are two peripheral controllers, an FDC, memory controller, video controller, and five custom ICs that contribute to the system’s compact design.**

この5つのチップは、ゲート数約6000〜7000個分、TTL30〜40個に換算されるという。  
**These five chips are equivalent to approximately 6000–7000 logic gates, or 30–40 TTL ICs.**

また、CMOSチップを多用することで発熱量を抑え、耳障りなファンを廃していることには好感が持てる。  
**Heavy use of CMOS chips keeps heat output low and allows for fanless, quiet operation—something that’s highly appreciated.**

ただし、このマシンの主たる使用目的と思われるビジネスユースを考えた場合、「多少うるさくても信頼性を求める」というユーザーも少なくないだろう。  
**However, considering its target as a business machine, there may be users who prefer a louder but more robust cooling system.**

---

## 今後のサポートが期待される周辺分野  
**Peripheral support anticipated in the future**

QC-11にはオプションとしてQCマウスというRS-232Cを使ったシリアルマウスがサポートされている（マウスドライバはすでにROMに組み込み）。  
**A serial RS-232C mouse called the QC Mouse is available as an option, with its driver already embedded in ROM.**

現在、マウスを使ったソフトウェアとしては「ユニペイント」というお絵描きツールがあるのみだが、今後、グラフィック以外の面にもマウスが活用されていくことを期待したい。  
**At present, only the "UniPaint" drawing tool uses the mouse, but future applications beyond graphics are anticipated.**

また、仕様表にもあるように、QC-11の本体前面にはROMカートリッジインターフェースが装備されている。  
**As listed in the specifications, the QC-11 features a ROM cartridge interface on the front panel.**

ROMカートリッジを使うことでQC-11は汎用機から専用機に生まれ変わることができるので、サポート態勢が整えば広い市場を獲得できる強力な武器になるだろう。  
**With cartridges, the QC-11 can transform from a general-purpose to a dedicated system—potentially expanding its market with the right software support.**

---

## 総評：地味だが好感の持てるマシン  
**Final Evaluation: A modest but well-designed machine**

日本のようにDISK-BASIC優勢の市場で、QC-11のようなOS標準装備のマシン（しかもROMで）の価値がどのくらい理解してもらえるか一抹の不安が残る。  
**In Japan’s DISK-BASIC-dominated market, there's concern over how much the value of a ROM-based OS machine like the QC-11 will be appreciated.**

しかし、MS-DOSのソフトウェア資産の豊富さと質の高さを理解するユーザーにとって、QC-11は魅力的な選択肢となるはずだ。  
**But for users who understand the quality and abundance of MS-DOS software, the QC-11 is an appealing option.**

今後、このマシンがユーザーの間に広まっていくかどうかは、すべてこのアプリケーション分野の充実にかかっているのかもしれない。  
**Ultimately, the spread of this machine will depend on how well the application ecosystem develops.**

---

📄 Original article: [`QC11-ARTICLE_.pdf`](QC11-ARTICLE_.pdf)  
📝 Source: ASCII Magazine (Japan), August 1985  
