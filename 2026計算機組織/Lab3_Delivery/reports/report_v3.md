# Lab 3 Assignment Report

## Student Information

Please enter your name and student ID below.

- Student Name: **彭靖翔**
- Student ID: **E24144773**

You may answer in English or Traditional Chinese. Explain your own implementation and refer to its signal names where helpful.

## CPU Implementation (20 pts)

1. **CPU architecture diagram:** Draw a diagram of your single-cycle CPU showing its modules, main datapath connections, and control signals. You may draw it by hand or use draw.io. Include a clear image in this report.
2. **Module implementation:** Explain how you implemented each of the nine modules: Reg_PC, RegFile, Decoder, Imme_Ext, ALU, JB_Unit, LD_Filter, Controller, and Top. Describe the main logic of each module and how Top connects them to form the CPU.

### Your Answer

### 1. CPU architecture diagram

![Single-cycle CPU architecture](cpu-architecture.svg)

**架構圖閱讀方式：** A 區呈現取指、解碼、讀取暫存器、運算、資料記憶體及寫回；B 區呈現 JB 加法、JALR 清 bit0 與 next-PC 選擇；C 區列出 Controller 到各 MUX／寫入介面的控制訊號。三區中的 `pc`、`imm`、`rs1_data`、`jump` 等名稱代表相同的共享 wire，不是三顆獨立 CPU。圖省略的重複支線，以以下訊號連接表與完整 Top.v 補足。

**時脈與狀態：** `clk` 接 PC、RegFile、IM 與 DM；`rst` 接 PC 與 RegFile 並用於 Top 的 store gating。IM/DM 使用助教提供的 SRAM，不修改其內部。一般順序指令的 next PC 為 `pc+4`；控制流指令則經 B 區選擇目標。


本 CPU 為 32-bit 單週期設計。架構圖分成主要資料路徑、next-PC 與控制訊號三區，三區是同一顆 CPU，透過相同訊號名稱連接。IF/ID/EX/MEM/WB 為同一週期內的工作；PC 與 RegFile 在上升緣更新。

#### 主要資料與控制連接

- `pc`：PC.current_pc → IM.address；PC+4、ALU/JB 的 PC 輸入。目前指令位址。
- `inst`：IM.read_data → Decoder.inst、Imme_Ext.inst。同一條指令供解碼與立即數產生。
- `rs1_data / rs2_data`：RegFile → ALU operand MUX；rs1 → JB MUX；rs2 → store shift。提供運算、分支與 store 來源。
- `imm`：Imme_Ext → ALU operand2 MUX、JB_Unit.operand2。立即數或已重組位移。
- `alu_out`：ALU → 記憶體定位邏輯及非 load 寫回路徑。結果或有效 byte address。
- `jump`：ALU → Controller.jump。branch 成立條件。
- `dm_read_data → ld_data → ld_data_f`：DM → Top 右移 → LD_Filter → wb_data。load 定位與擴展。
- `wb_data`：Top 寫回 MUX → regfile.wb_data。邊緣更新 rd。
- `jb_out → jb_pc → next_pc`：JB → JALR bit0 修正 → Next-PC MUX → PC.next_pc。控制流更新。

#### 控制訊號編碼

- `next_pc_sel`：0:pc_plus4；1:jb_pc；branch 看 jump，JAL/JALR 為1。
- `jb_op1_sel`：0:pc；1:rs1_data；JALR 為1。
- `alu_op1_sel`：0:rs1_data；1:pc；AUIPC 為1。
- `alu_op2_sel`：0:rs2_data；1:imm；I/load/store/LUI/AUIPC 為1。
- `wb_en`：1 啟用 rd 寫入；Top 再 AND rst；store/branch 為0；x0 仍禁止寫。
- `wb_sel`：0:非load；1:ld_data_f；非load 額外判斷 JAL/JALR 選 pc_plus4。
- `dm_w_en`：SB=0001；SH=0011；SW=1111；Top 位移並在 reset 清零。
- `im_w_en`：固定0000；執行期間禁止寫 IM。
- `alu_opcode/func3/func7`：轉送操作欄位至 ALU；與 Decoder 的介面寬度相符。

### 2. Module implementation

#### Reg_PC

Reg_PC 是保存目前指令位址的 32-bit 狀態元件。使用 always @(posedge clk or negedge rst)；rst=0 時以非阻塞指派將 current_pc 清為零，否則在時脈上升緣更新為 next_pc。

在 Top 內使用指定 instance 名稱 PC，current_pc 接至 pc；next_pc 先由 Top 選擇。因此本模組不自行固定加 4，能接收循序或跳轉位址。

**實作步驟、設計理由與驗證重點**


**目的｜為什麼需要**

CPU 必須記住目前指令位址。PC 是跨週期保存的狀態，不能只用組合加法或一般 wire 代替。此模組只保存位址，下一個位址如何選擇交由 Top。


**開發步驟｜How**

先確認 current_pc 與 next_pc 均為 32 bits；接著寫 always @(posedge clk or negedge rst)。先處理 if (!rst) 清零，再用 else current_pc <= next_pc 完成正常更新。最後測試 reset 不在時脈邊緣時是否也立即生效。


**設計理由｜Why**

negedge rst 對應低有效非同步重置。非阻塞指派 <= 用於時序元件，讓同一上升緣依邊緣前的狀態完成更新。若在本模組固定加 4，就無法讓 Top 自由選擇分支或跳轉位址。


**實作位置與連接**

查看原始碼中的 always 區塊，以及 Top 的 Reg_PC PC 實例。Top 先計算 pc_plus4 與 jb_pc，再透過 next_pc_sel 選出 next_pc。PC 實例名稱及 current_pc 名稱須保留給驗證框架。


**預期結果｜Result**

rst=0 時 current_pc=0；rst=1 且 next_pc=4，在下一個上升緣後 current_pc=4。若邊緣前 next_pc=0x100，更新後就是 0x100。這些是規格推導值，並非本頁即時執行結果。


**驗證與常見錯誤**

檢查兩個上升緣之間 PC 是否保持；在非上升緣拉低 rst 應立即清零。若 reset 僅放在 posedge 區塊內，就變成同步 reset，不符合題意。


**對應完整程式碼：`rtl/src/Reg_PC.v`**

```verilog
// Lab3 RV32I 單周期 CPU｜中文註解實作
module Reg_PC (
	input clk,
	input rst,
	input [31:0] next_pc,
	output reg [31:0] current_pc
);

// 低有效、非同步重置；每個正緣提交一條指令的下一個 PC。
always @(posedge clk or negedge rst) begin
    if (!rst) current_pc <= 32'b0;
    else current_pc <= next_pc;
end

endmodule
```

#### RegFile

RegFile 宣告 reg [31:0] registers [0:31]，提供兩個組合讀埠與一個上升緣寫埠。低有效非同步 reset 會清除所有暫存器；正常時只有 wb_en 且 rd_index!=0 才更新目的暫存器。

registers[0] 持續保持零，讀取 index=0 時也直接輸出零。其餘讀取依 rs1_index、rs2_index 取得對應元素，不受 wb_en 限制。Top 的 instance 名為 regfile，寫入使能接 wb_en && rst。x2 不設特殊初值，由 runtime 初始化。

**實作步驟、設計理由與驗證重點**


**目的｜為什麼需要**

暫存器檔提供每條指令的來源與目的資料；兩個讀埠同時供 rs1、rs2，單一寫埠在指令完成時更新 rd。


**開發步驟｜How**

先宣告指定陣列 reg [31:0] registers [0:31]；再用時序 always 在 reset 時迴圈清除 32 個元素。正常時先維持 registers[0]=0，只有 wb_en 且 rd_index!=0 才寫入。另寫 always @(*)，依兩個 index 讀值，index=0 時直接輸出 0。


**設計理由｜Why**

讀取與寫入分成組合、時序兩條路徑，讓同一週期能讀來源、運算並在邊緣寫回。x0 的寫入防護與讀取固定零互相配合，符合 ISA。x2 不特別初始化，因為 stack pointer 由 runtime 設定。


**實作位置與連接**

時序區塊負責 registers；組合區塊產生 rs1_data_out、rs2_data_out。Top 的 regfile 使用 wb_en && rst，並把 Decoder 的 rd/rs 索引接入；來源資料分別流向 ALU、JB 路徑與 store 資料路徑。


**預期結果｜Result**

wb_en=1、rd_index=5、wb_data=10：上升緣後 registers[5]=10。wb_en=0 時保持舊值；rd_index=0 時忽略寫入。讀 rs1_index=5 得 10，讀 rs2_index=0 得 0。


**驗證與常見錯誤**

加入寫 x0、同一暫存器讀寫、reset 與雙讀埠測試。非阻塞指派在模擬更新階段生效；邊緣後組合讀埠會反映新值，不能理解成整個下一週期仍固定讀舊值。


**對應完整程式碼：`rtl/src/RegFile.v`**

```verilog
// Lab3 RV32I 單周期 CPU｜中文註解實作
module RegFile (
	input clk,
	input rst,
	input wb_en,
	input [31:0] wb_data,
	input [4:0] rd_index,
	input [4:0] rs1_index,
	input [4:0] rs2_index,
	output reg [31:0] rs1_data_out,
	output reg [31:0] rs2_data_out
);

// 平台透過 regfile.registers 讀取架構狀態，名稱不可更改。
reg [31:0] registers [0:31];
integer i;
// 寫入在正緣發生；非阻塞指派讓本周期仍讀取舊的來源暫存器。
always @(posedge clk or negedge rst) begin
    if (!rst) begin
        for (i = 0; i < 32; i = i + 1) registers[i] <= 32'b0;
    end else begin
        // x0 是硬接線的零；任何試圖寫入 x0 的指令都不改變它。
        registers[0] <= 32'b0;
        if (wb_en && rd_index != 5'b0) registers[rd_index] <= wb_data;
    end
end
// 雙讀埠為組合邏輯，同一周期即可供 ALU、分支及 store 使用。
always @(*) begin
    rs1_data_out = (rs1_index == 0) ? 32'b0 : registers[rs1_index];
    rs2_data_out = (rs2_index == 0) ? 32'b0 : registers[rs2_index];
end

endmodule
```

**時序補充：** 上述原始碼註解所說的「讀取舊來源」，指上升緣取樣與非阻塞更新前的狀態；非阻塞更新完成後，組合讀埠會隨陣列的新值重新計算，並非整個下一週期仍固定輸出舊值。

#### Decoder

Decoder 為純組合欄位擷取：dc_out_opcode=inst[6:2]、dc_out_func3=inst[14:12]、dc_out_func7=inst[30]，rs1/rs2/rd 索引分別取 inst[19:15]、inst[24:20]、inst[11:7]。

本介面 opcode 只有 5 bits、func7 只有 1 bit。Top 將操作欄位送給 Controller，索引送給 RegFile；某些格式不使用的來源欄位仍可擷取，由後續 MUX 忽略。

**實作步驟、設計理由與驗證重點**


**目的｜為什麼需要**

把 32-bit 指令拆成固定欄位，供 Controller 決定動作、RegFile 決定讀寫位置。Decoder 不負責實際運算，也不決定所有欄位是否有效。


**開發步驟｜How**

先對照介面寬度，再逐一連接 inst[6:2]、inst[14:12]、inst[30]、inst[19:15]、inst[24:20]、inst[11:7]。使用完整賦值的組合 always，不需要 clk。


**設計理由｜Why**

本作業省略 opcode 最低兩位，func7 也只留 bit30。依介面取位可避免寬度截斷與錯誤解碼。所有格式都直接擷取固定位置，再讓後續控制忽略不需要的欄位，能簡化電路。


**實作位置與連接**

查看 dc_out_* 的六個指派。Top 將 opcode/func3/func7 接 Controller，將三個 index 接 RegFile。ADDI 中被當成 rs2_index 的位元實際屬於立即數，但 ALU 輸入選 imm，所以該讀埠結果不影響運算。


**預期結果｜Result**

addi x5,x0,10 的機器碼為 0x00A00293，應解出 opcode=00100、func3=000、func7=0、rs1=0、rd=5；rs2_index 會擷取到 10，但此指令不使用該資料。


**驗證與常見錯誤**

以已知機器碼逐欄位對照。不要把 inst[6:0] 直接當成 5-bit 輸出，也不要把完整 funct7 當成 1-bit func7。


**對應完整程式碼：`rtl/src/Decoder.v`**

```verilog
// Lab3 RV32I 單周期 CPU｜中文註解實作
module Decoder (
	input [31:0] inst,
	output reg [4:0] dc_out_opcode,
	output reg [2:0] dc_out_func3,
	output reg dc_out_func7,
	output reg [4:0] dc_out_rs1_index,
	output reg [4:0] dc_out_rs2_index,
	output reg [4:0] dc_out_rd_index
);

// 本作業 opcode 只取 [6:2]；func7 只取 bit30，並非完整七位欄位。
// 固定位置的欄位直接接出；不使用的欄位由 Controller 忽略。
always @(*) begin
    dc_out_opcode = inst[6:2];
    dc_out_func3 = inst[14:12];
    dc_out_func7 = inst[30];
    dc_out_rs1_index = inst[19:15];
    dc_out_rs2_index = inst[24:20];
    dc_out_rd_index = inst[11:7];
end

endmodule
```

#### Imme_Ext

Imme_Ext 從 inst[6:2] 判斷格式，沒有額外 ImmSel port。I 型取 inst[31:20]；S 型拼接 inst[31:25] 與 inst[11:7]。B 型依 inst[31]、inst[7]、inst[30:25]、inst[11:8]、0 重組；J 型依 inst[31]、inst[19:12]、inst[20]、inst[30:21]、0 重組。

I/S/B/J 皆符號延伸至 32 bits；B/J 已包含最低位 0，不再額外左移。U 型使用 {inst[31:12],12'b0}。組合邏輯先給預設零，所有路徑完整賦值；imm 在 Top 同時供給 ALU operand2 MUX 與 JB_Unit。

**實作步驟、設計理由與驗證重點**


**目的｜為什麼需要**

不同格式把常數或位移分散在不同指令位元，CPU 需要重建為統一的 32-bit immediate，供 ALU 與 JB_Unit 使用。


**開發步驟｜How**

先將 imm_ext_out 預設為 0，再依 inst[6:2] 分類。I 型取 [31:20]；S 型合併 [31:25] 與 [11:7]；B 型依符號、bit7、[30:25]、[11:8]、0 排列；U 型取 [31:12] 接 12 個零；J 型依符號、[19:12]、bit20、[30:21]、0 排列。


**設計理由｜Why**

I/S/B/J 需符號延伸，才能表示負常數與向後跳轉。B/J 的最低位是隱含零，這裡已補入，後面不能再把整個位移左移一次。每條路徑完整賦值可避免不必要的 latch。


**實作位置與連接**

查看 case (inst[6:2]) 的各分支。本介面沒有 ImmSel，模組自行分類。Top 的 imm 同時接 ALU operand2 選擇器及 JB_Unit 的 operand2。Shift-immediate 雖使用 I 型輸出，但 ALU 只使用 operand2[4:0] 作位移量。


**預期結果｜Result**

I 型 -1 → 0xFFFFFFFF；S 型 -4 → 0xFFFFFFFC；B 型 -8 → 0xFFFFFFF8；U 高位值 0x12345 → 0x12345000；J 型 +8 → 0x00000008。


**驗證與常見錯誤**

以正值、負值與位元邊界檢查每種格式。B 型的 inst[7] 與 J 型的 inst[20] 容易接錯；所有拼接結果必須剛好 32 bits。


**對應完整程式碼：`rtl/src/Imme_Ext.v`**

```verilog
// Lab3 RV32I 單周期 CPU｜中文註解實作
module Imme_Ext (
	input [31:0] inst,
	output reg [31:0] imm_ext_out
);

// 每條指令自行決定立即數格式；分支及 JAL 的 bit0 固定為零。
// 所有輸出完整賦值，避免組合邏輯意外推導出 latch。
always @(*) begin
    imm_ext_out = 32'b0;
    case (inst[6:2])
        5'b00100, 5'b00000, 5'b11001: // I: ALU immediate / load / JALR
            imm_ext_out = {{20{inst[31]}}, inst[31:20]};
        5'b01000: // S: store 的立即數分散在兩個欄位
            imm_ext_out = {{20{inst[31]}}, inst[31:25], inst[11:7]};
        5'b11000: // B: 符號延伸 13-bit 位移（已包含最低位零）
            imm_ext_out = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
        5'b01101, 5'b00101: // U: LUI / AUIPC
            imm_ext_out = {inst[31:12], 12'b0};
        5'b11011: // J: 符號延伸 21-bit 位移
            imm_ext_out = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};
        default: imm_ext_out = 32'b0;
    endcase
end

endmodule
```

#### ALU

ALU 在組合 always 先令 alu_out=0、jump=0，再依 opcode 與 func3 選擇操作。R/I 型支援加減、位移、比較、XOR、OR、AND；SUB 只在 R-type 且 func7=1 時使用，避免將負數 ADDI 的 bit30 誤判為減法。

SLT 與 BLT/BGE 以 $signed 比較；SLTU 與 BLTU/BGEU 使用無號比較。位移量只取 operand2[4:0]；SRA 使用 $signed(operand1) >>>，SRL 使用 >>。load/store 與 AUIPC 做加法，LUI 直接傳 operand2。

branch 類別依 func3 輸出 BEQ/BNE/BLT/BGE/BLTU/BGEU 的 jump，非 branch 保持 jump=0。條件比較與跳轉位址分開，位址由 JB_Unit 計算。

**實作步驟、設計理由與驗證重點**


**目的｜為什麼需要**

重用同一運算單元執行算術、邏輯、位移、比較與記憶體有效位址計算，並產生 branch 的成立旗標 jump。


**開發步驟｜How**

先將 alu_out 與 jump 預設為 0；外層用 opcode 區分 R/I、load/store/AUIPC、LUI 與 branch。R/I 內層依 func3 選操作；加減法只對 R-type 使用 func7。右移依 func7 選 >> 或 signed >>>。branch 內依 func3 設 jump。


**設計理由｜Why**

ADDI 的 bit30 是立即數的一部分，不能當成 SUB 控制。算術右移必須讓左運算元為 signed；有號比較也使用 $signed，無號比較保留原本 unsigned。只取位移量低五位，避免將其他立即數位元當成位移量。


**實作位置與連接**

opcode=01100/00100 處理算術；00000/01000/00101 做加法；01101 直接傳 operand2；11000 產生分支比較。Controller 轉送 ALU 解碼資訊，Top 決定 operand1 是 PC/rs1、operand2 是 imm/rs2。


**預期結果｜Result**

ADDI 0+(-1) → FFFFFFFF；SLT 比較 FFFFFFFF 與 1 → 1，SLTU → 0；FFFFFFF8 SRA 1 → FFFFFFFC、SRL 1 → 7FFFFFFC；BEQ 相等時 jump=1；非 branch jump=0。32-bit 加法溢出保留低 32 bits。


**驗證與常見錯誤**

分別測負數、相等、最大最小值、位移 0/31、分支成立與不成立。LUI 不應受 rs1 影響；branch 比較結果使用 jump，不是把 ALU 比較值誤當目標位址。


**對應完整程式碼：`rtl/src/ALU.v`**

```verilog
// Lab3 RV32I 單周期 CPU｜中文註解實作
module ALU (
	input [4:0] opcode,
	input [2:0] func3,
	input func7,
	input [31:0] operand1,
	input [31:0] operand2,
	output reg [31:0] alu_out,
	output reg jump
);

// opcode 是 inst[6:2]；所有結果保持 32 bits，自然保留模 2^32 結果。
always @(*) begin
    alu_out = 32'b0;
    jump = 1'b0;
    case (opcode)
        5'b01100, 5'b00100: begin // R-type 與 I-type 算術
            case (func3)
                // I-type bit30 屬立即數，ADDI 不可因它為 1 而變成 SUB。
                3'b000: alu_out = (opcode == 5'b01100 && func7)
                                   ? operand1 - operand2 : operand1 + operand2;
                3'b001: alu_out = operand1 << operand2[4:0];
                // 比較輸出只有 bit0 有意義，其餘 31 bits 補零。
                3'b010: alu_out = {31'b0, ($signed(operand1) < $signed(operand2))};
                3'b011: alu_out = {31'b0, (operand1 < operand2)};
                3'b100: alu_out = operand1 ^ operand2;
                // >>> 必須搭配 signed 左運算元，才能複製符號位。
                3'b101: begin
                    if (func7) alu_out = $signed(operand1) >>> operand2[4:0];
                    else alu_out = operand1 >> operand2[4:0];
                end
                3'b110: alu_out = operand1 | operand2;
                3'b111: alu_out = operand1 & operand2;
                default: alu_out = 32'b0;
            endcase
        end
        5'b00000, 5'b01000, 5'b00101: // load/store 位址、AUIPC
            alu_out = operand1 + operand2;
        5'b01101: alu_out = operand2; // LUI 不使用 rs1
        5'b11000: begin // 分支只比較 rs1/rs2，不在這裡計算跳轉目標
            case (func3)
                3'b000: jump = (operand1 == operand2); // BEQ
                3'b001: jump = (operand1 != operand2); // BNE
                3'b100: jump = ($signed(operand1) < $signed(operand2)); // BLT
                3'b101: jump = ($signed(operand1) >= $signed(operand2)); // BGE
                3'b110: jump = (operand1 < operand2); // BLTU
                3'b111: jump = (operand1 >= operand2); // BGEU
                default: jump = 1'b0;
            endcase
        end
        default: begin alu_out = 32'b0; jump = 1'b0; end
    endcase
end

endmodule
```

#### JB_Unit

JB_Unit 是 32-bit 組合加法器，輸出 jb_out=operand1+operand2。Top 依 jb_op1_sel 決定 operand1 使用 pc 或 rs1_data，operand2 接 imm。

branch 與 JAL 使用 pc+imm；JALR 使用 rs1_data+imm，Top 再將 jb_out 最低位清零形成 jb_pc。JB_Unit 本身不解碼指令，也不再對 imm 做額外位移。

**實作步驟、設計理由與驗證重點**


**目的｜為什麼需要**

分支與跳轉都需要基底加位移。獨立加法器可在 ALU 比較 branch 來源值時，同時算好跳轉目標。


**開發步驟｜How**

先定義兩個 32-bit 輸入與一個 32-bit 輸出；組合 always 只做 jb_out=operand1+operand2。Top 另用 jb_op1_sel 選基底，並處理 JALR 最低位清零。


**設計理由｜Why**

JB_Unit 不需要 opcode，保持單純加法功能。branch/JAL 用 PC，JALR 用 rs1；把基底與格式特殊處理放 Top，可共用一個單元。


**實作位置與連接**

查看 JB_Unit 的加法，以及 Top 的 jb_operand1、jb_out、jb_pc。Controller 對 JALR 將 jb_op1_sel 設為 1，其餘 branch/JAL 使用預設 PC。


**預期結果｜Result**

PC=0x100、imm=-8 → jb_out=0xF8。JALR rs1=0x101、imm=2 → jb_out=0x103，Top 清 bit0 後 jb_pc=0x102。後者只是目標計算示例，不表示測試程式一定從該半字對齊位址取指。


**驗證與常見錯誤**

檢查負位移與加法回繞。不要在 JB_Unit 把所有指令目標都強制清除低兩位，也不要對 B/J 的 imm 再左移一次。


**對應完整程式碼：`rtl/src/JB_Unit.v`**

```verilog
// Lab3 RV32I 單周期 CPU｜中文註解實作
module JB_Unit (
	input [31:0] operand1,
	input [31:0] operand2,
	output reg [31:0] jb_out
);

// branch/JAL 的基底是 PC，JALR 的基底是 rs1；由 Top 選擇。
// 此處只加法，JALR 清除最低位的工作留給 Top。
always @(*) begin
    jb_out = operand1 + operand2;
end

endmodule
```

#### LD_Filter

LD_Filter 接收已由 Top 右移定位的 ld_data，依 func3 決定 load 寬度。LB 將 bit7 符號延伸，LH 將 bit15 符號延伸；LBU/LHU 高位補零；LW 原值通過，其他選項輸出零。

模組沒有位址輸入，不負責 byte lane 選擇。Top 先做 dm_read_data >> byte_shift，再送入 LD_Filter，確保擴展使用正確符號位。ld_data_f 最後經寫回 MUX 送入 RegFile。

**實作步驟、設計理由與驗證重點**


**目的｜為什麼需要**

SRAM 回傳 32-bit word，但 LB/LH 只讀部分資料，且 signed/unsigned 的高位補法不同。本模組統一產生最終寫回值。


**開發步驟｜How**

先約定 Top 已將目標 byte/halfword 右移到低位。依 func3 選 LB、LH、LW、LBU、LHU；LB 複製 bit7 共 24 次，LH 複製 bit15 共 16 次；unsigned 高位補零；LW 原值通過；其他值回零。


**設計理由｜Why**

本模組沒有 address 輸入，因此不能自行選 byte lane。先定位再擴展才能選到正確符號位；若直接用原始 word 的 bit7，就會在 offset 非零時出錯。


**實作位置與連接**

Top 先計算 ld_data=dm_read_data>>byte_shift，再將 func3、ld_data 接入此模組。輸出 ld_data_f 經 wb_sel 選擇後回寫 RegFile。


**預期結果｜Result**

ld_data 低 byte=0x80：LB 得 FFFFFF80、LBU 得 00000080。低 halfword=0x8000：LH 得 FFFF8000、LHU 得 00008000。LW 得完整 ld_data。


**驗證與常見錯誤**

同時測正負 byte、正負 halfword、不同 offset，以及 LW。partial_access_test 能檢查多種定位與擴展情境。不要讓組合 always 的某個 func3 路徑漏賦值。


**對應完整程式碼：`rtl/src/LD_Filter.v`**

```verilog
// Lab3 RV32I 單周期 CPU｜中文註解實作
module LD_Filter (
	input [2:0] func3,
	input [31:0] ld_data,
	output reg [31:0] ld_data_f
);

// Top 已把需要的 byte 移到最低位；此模組只負責寬度及符號。
always @(*) begin
    case (func3)
        3'b000: ld_data_f = {{24{ld_data[7]}}, ld_data[7:0]};   // LB
        3'b001: ld_data_f = {{16{ld_data[15]}}, ld_data[15:0]}; // LH
        3'b010: ld_data_f = ld_data;                          // LW
        3'b100: ld_data_f = {24'b0, ld_data[7:0]};             // LBU
        3'b101: ld_data_f = {16'b0, ld_data[15:0]};            // LHU
        default: ld_data_f = 32'b0;
    endcase
end

endmodule
```

#### Controller

Controller 是組合控制邏輯，先設定安全預設：不寫 rd/IM/DM，PC 選循序路徑，ALU 預設 rs1/rs2，並轉送 alu_opcode、alu_func3、alu_func7。每種指令再覆寫必要控制，避免保留上一條指令的控制值。

R-type、I-type、load、LUI、AUIPC、JAL/JALR 啟用 wb_en；store 與 branch 不啟用。I/load/store/LUI/AUIPC 選 imm；AUIPC 的 ALU 第一輸入選 pc。branch 的 next_pc_sel=jump，JAL/JALR 無條件選跳轉，JALR 的 jb_op1_sel=1。

wb_sel=1 代表 load，非 load 使用 0；JAL/JALR 的 PC+4 寫回由 Top 額外判斷。SB/SH/SW 的基本 dm_w_en 分別為 0001/0011/1111，位移由 Top 完成；im_w_en 固定 0000。

**實作步驟、設計理由與驗證重點**


**目的｜為什麼需要**

同一資料路徑要支援多種指令，Controller 決定每條指令的資料來源、寫入動作與 PC 更新方式。


**開發步驟｜How**

先設定安全預設：PC+4、不寫 rd、不寫 IM/DM、ALU 選 rs1/rs2，並轉送 opcode/func3/func7。再以 opcode 啟用各指令需要的控制：I/load/store 選 imm；load 選記憶體寫回；store 依 func3 決定 mask；branch 使用 jump；JAL/JALR 強制跳轉；AUIPC 選 PC+imm。


**設計理由｜Why**

先給全部輸出預設值可避免 latch 或沿用上一條指令的寫入使能。store/branch 不寫 rd。wb_sel 只有 1 bit，所以只區分 load/非 load；JAL/JALR 的 PC+4 寫回由 Top 再判斷。


**實作位置與連接**

MUX 編碼與 Top 必須一致：jb_op1_sel 0=PC/1=rs1；alu_op1_sel 0=rs1/1=PC；alu_op2_sel 0=rs2/1=imm；wb_sel 0=非load/1=load。im_w_en 始終 0000。


**預期結果｜Result**

R-type：wb_en=1，DM mask=0；SB/SH/SW 基本 mask=0001/0011/1111，wb_en=0；branch 的 next_pc_sel=jump；JAL/JALR 的 next_pc_sel=1 且 wb_en=1；AUIPC 的兩個 ALU 輸入為 PC 與 imm。


**驗證與常見錯誤**

以每類指令建立控制表，對照 Top 的 ternary MUX。基本 mask 不在此處按地址位移，因 Controller 沒有地址輸入。非法編碼與例外不屬於本作業完整實作範圍，不應宣稱此解碼器具備完整例外處理。


**對應完整程式碼：`rtl/src/Controller.v`**

```verilog
// Lab3 RV32I 單周期 CPU｜中文註解實作
module Controller(
	input [4:0] opcode,
	input [2:0] func3,
    	input func7,
    	input jump,
	output reg next_pc_sel,
	output reg [3:0] im_w_en,
	output reg wb_en,
	output reg jb_op1_sel,
	output reg alu_op1_sel,
	output reg alu_op2_sel,
	output reg [4:0] alu_opcode,
	output reg [2:0] alu_func3,
	output reg alu_func7,
	output reg wb_sel,
	output reg [3:0] dm_w_en
);

// MUX 編碼約定（與 Top 一致）：
// jb_op1_sel: 0=PC, 1=rs1；alu_op1_sel: 0=rs1, 1=PC。
// alu_op2_sel: 0=rs2, 1=imm；wb_sel: 0=非 load, 1=load。
always @(*) begin
    // 安全預設：不寫任何記憶體、不寫暫存器、PC 往前四位元組。
    next_pc_sel = 1'b0;
    im_w_en = 4'b0000;
    wb_en = 1'b0;
    jb_op1_sel = 1'b0;
    alu_op1_sel = 1'b0;
    alu_op2_sel = 1'b0;
    alu_opcode = opcode;
    alu_func3 = func3;
    alu_func7 = func7;
    wb_sel = 1'b0;
    dm_w_en = 4'b0000;
    case (opcode)
        5'b01100: wb_en = 1'b1; // R-type
        5'b00100: begin wb_en = 1'b1; alu_op2_sel = 1'b1; end
        5'b00000: begin // Load: ALU 產生位址，回寫經 LD_Filter 處理的值
            wb_en = 1'b1; alu_op2_sel = 1'b1; wb_sel = 1'b1;
        end
        5'b01000: begin // Store: 這只是未依 offset 平移的基本 mask
            alu_op2_sel = 1'b1;
            case (func3)
                3'b000: dm_w_en = 4'b0001;
                3'b001: dm_w_en = 4'b0011;
                3'b010: dm_w_en = 4'b1111;
                default: dm_w_en = 4'b0000;
            endcase
        end
        5'b11000: next_pc_sel = jump; // 分支條件來自 ALU
        5'b11011: begin wb_en = 1'b1; next_pc_sel = 1'b1; end // JAL
        5'b11001: begin // JALR 的目標基底與 JAL 不同
            wb_en = 1'b1; next_pc_sel = 1'b1; jb_op1_sel = 1'b1;
        end
        5'b01101: begin wb_en = 1'b1; alu_op2_sel = 1'b1; end // LUI
        5'b00101: begin // AUIPC = 當前 PC + U-immediate
            wb_en = 1'b1; alu_op1_sel = 1'b1; alu_op2_sel = 1'b1;
        end
        default: begin end
    endcase
end

endmodule
```

#### Top

Top 實例化九個模組中的其餘八個以及兩個提供的 SRAM。保留 PC、regfile、IM、DM 名稱。IM 使用 READ_ONLY=1，DM 使用 READ_ONLY=0；PC 與 RegFile 接 clk/rst，兩個 SRAM 接 clk。

取指後 inst 同時送 Decoder 與 Imme_Ext；RegFile 輸出 rs1_data、rs2_data。alu_op1_sel 決定 pc 或 rs1_data，alu_op2_sel 決定 imm 或 rs2_data；ALU 計算結果與 branch 的 jump。

pc_plus4=pc+4；JB_Unit 依基底與 imm 產生 jb_out，JALR 清 bit0 得 jb_pc。next_pc=next_pc_sel ? jb_pc : pc_plus4。寫回則為 load 選 ld_data_f，JAL/JALR 選 pc_plus4，其餘選 alu_out。

資料記憶體使用 byte_offset=alu_out[1:0]、byte_shift={byte_offset,3'b000}、dm_address={alu_out[31:2],2'b00}。store 資料左移 byte_shift，基本 mask 左移 byte_offset；rst=0 時最終 dm_mask=0000。load 將 dm_read_data 右移 byte_shift 後交 LD_Filter。

支援題目保證不跨 word 的 byte、halfword、word 存取，包括 halfword offset 1。DM.halt 直接接 Top.halt；IM 的 halt 在本實作接未使用的 im_halt_unused wire，不驅動 CPU 結束。此與題目示範留空的效果相同。結束由正常 store 將 byte 1 寫至 0xFFFFFFFB 觸發，不需要 ECALL。

**實作步驟、設計理由與驗證重點**


**目的｜為什麼需要**

把八個子模組、兩個 SRAM 與選擇器接成 CPU。單一模組正確仍不保證整體正確，Top 決定完整資料如何流動。


**開發步驟 1｜取指與解碼**

宣告各訊號，連接 Reg_PC PC、SRAM IM、Decoder 與 Imme_Ext。計算 pc_plus4=pc+4。IM 使用 READ_ONLY=1；Controller 讓 im_w_en 固定為零。


**開發步驟 2｜讀取、控制與運算**

連接 RegFile regfile 與 Controller。依 alu_op1_sel 選 PC/rs1，依 alu_op2_sel 選 imm/rs2，送入 ALU；ALU.jump 回授 Controller，判斷 branch 是否成立。


**開發步驟 3｜跳轉與寫回**

JB 基底依 jb_op1_sel 選 PC/rs1，加 imm 得 jb_out；JALR 清 bit0 得 jb_pc。next_pc_sel 選 jb_pc 或 pc_plus4。寫回先判斷 load，再判斷 JAL/JALR，最後才用 alu_out。


**開發步驟 4｜記憶體定位**

取 alu_out[1:0] 為 offset，拼接三個零得到 0/8/16/24-bit shift；地址低兩位歸零。Store 將 rs2_data 與基本 mask 同方向左移；load 將 SRAM 讀值右移後交 LD_Filter。rst=0 時 dm_mask 強制歸零。


**設計理由｜Why**

SRAM 以 word 為單位，指令以 byte 為地址，所以資料、mask、位址必須一致處理。只移 mask 或只移資料都會寫錯位置。halfword offset 1 須支援，但題目保證不跨 word，不需要雙 word 合併。


**實作位置與連接**

重點 assign：next_pc、alu_operand1/2、jb_operand1、jb_pc、byte_offset、byte_shift、dm_address、dm_write_data、dm_mask、ld_data、wb_data。DM 使用 READ_ONLY=0，halt 直接接 Top.halt。PC/regfile/IM/DM 名稱不可改。


**預期結果｜Result**

SB offset3、rs2低byte=AB：對齊地址低兩位為0、mask1000、資料AB000000。SH offset1、rs2低halfword=1234：mask0110、資料00123400。Load offset1 右移8後再擴展。終止 store 向FFFFFFFB寫byte1，經正常 store 路徑觸發 DM.halt。


**整體驗證與除錯**

依序檢查 reset → ADDI/ADD → load/store → branch → JAL/JALR → partial access → 全部七項測試。修改 RTL 後先 build，再 CTest。用第一個 CrossVerify mismatch 找錯誤週期，對照上升緣前運算與邊緣後狀態。以上為用於驗證與除錯的建議順序。


**對應完整程式碼：`rtl/src/Top.v`**

```verilog
// Lab3 RV32I 單周期 CPU｜中文註解實作
module Top(
    input clk,
    input rst,
    output halt
);

// 平台會透過階層名稱讀取 PC、regfile、IM、DM，以下名稱須保留。
wire [31:0] pc, pc_plus4, next_pc, inst, imm;
wire [4:0] opcode, rs1_index, rs2_index, rd_index;
wire [2:0] func3;
wire func7;
wire [31:0] rs1_data, rs2_data, alu_operand1, alu_operand2, alu_out;
wire jump, next_pc_sel, wb_en, jb_op1_sel, alu_op1_sel, alu_op2_sel, wb_sel;
wire [4:0] alu_opcode;
wire [2:0] alu_func3;
wire alu_func7;
wire [3:0] im_w_en, dm_w_en, dm_mask;
wire [31:0] jb_operand1, jb_out, jb_pc;
wire [31:0] dm_address, dm_write_data, dm_read_data, ld_data, ld_data_f, wb_data;
wire im_halt_unused;
wire [1:0] byte_offset;
wire [4:0] byte_shift;

assign pc_plus4 = pc + 32'd4;
assign next_pc = next_pc_sel ? jb_pc : pc_plus4;
Reg_PC PC (.clk(clk), .rst(rst), .next_pc(next_pc), .current_pc(pc));
// 程式由 testbench 載入 IM.rom；CPU 執行期間不寫 IM。
SRAM #(.READ_ONLY(1)) IM (
    .clk(clk), .w_en(im_w_en), .address(pc), .write_data(32'b0),
    .read_data(inst), .halt(im_halt_unused)
);
Decoder decoder (
    .inst(inst), .dc_out_opcode(opcode), .dc_out_func3(func3), .dc_out_func7(func7),
    .dc_out_rs1_index(rs1_index), .dc_out_rs2_index(rs2_index), .dc_out_rd_index(rd_index)
);
Imme_Ext imme_ext (.inst(inst), .imm_ext_out(imm));
RegFile regfile (
    .clk(clk), .rst(rst), .wb_en(wb_en && rst), .wb_data(wb_data),
    .rd_index(rd_index), .rs1_index(rs1_index), .rs2_index(rs2_index),
    .rs1_data_out(rs1_data), .rs2_data_out(rs2_data)
);
Controller controller (
    .opcode(opcode), .func3(func3), .func7(func7), .jump(jump),
    .next_pc_sel(next_pc_sel), .im_w_en(im_w_en), .wb_en(wb_en),
    .jb_op1_sel(jb_op1_sel), .alu_op1_sel(alu_op1_sel), .alu_op2_sel(alu_op2_sel),
    .alu_opcode(alu_opcode), .alu_func3(alu_func3), .alu_func7(alu_func7),
    .wb_sel(wb_sel), .dm_w_en(dm_w_en)
);
assign alu_operand1 = alu_op1_sel ? pc : rs1_data;
assign alu_operand2 = alu_op2_sel ? imm : rs2_data;
ALU alu (
    .opcode(alu_opcode), .func3(alu_func3), .func7(alu_func7),
    .operand1(alu_operand1), .operand2(alu_operand2), .alu_out(alu_out), .jump(jump)
);
assign jb_operand1 = jb_op1_sel ? rs1_data : pc;
JB_Unit jb_unit (.operand1(jb_operand1), .operand2(imm), .jb_out(jb_out));
// JALR 強制 bit0=0；branch/JAL 保留立即數產生器給出的位移。
assign jb_pc = (opcode == 5'b11001) ? {jb_out[31:1], 1'b0} : jb_out;

// Little-endian：SRAM 一次傳回一個 word；CPU 用低兩位選 byte lane。
assign byte_offset = alu_out[1:0];
assign byte_shift = {byte_offset, 3'b000}; // offset * 8，範圍 0/8/16/24
assign dm_address = {alu_out[31:2], 2'b00};
assign dm_write_data = rs2_data << byte_shift;
// Store mask 和資料必須一起向左平移；reset 期間禁止記憶體寫入。
assign dm_mask = rst ? (dm_w_en << byte_offset) : 4'b0000;
SRAM #(.READ_ONLY(0)) DM (
    .clk(clk), .w_en(dm_mask), .address(dm_address), .write_data(dm_write_data),
    .read_data(dm_read_data), .halt(halt)
);
// Load 先右移，再做 sign/zero extension，否則 offset 非零時會取錯符號位。
// 題目保證存取不跨 word，故不需要讀取第二個 word。
assign ld_data = dm_read_data >> byte_shift;
LD_Filter ld_filter (.func3(func3), .ld_data(ld_data), .ld_data_f(ld_data_f));
// Load 回寫資料；JAL/JALR 回寫 return address；其他指令回寫 ALU 結果。
assign wb_data = wb_sel ? ld_data_f :
                 ((opcode == 5'b11011 || opcode == 5'b11001) ? pc_plus4 : alu_out);

endmodule
```

### Instruction control and integration table

下表的 0/1 編碼以本實作 Controller 與 Top 為準。「—」表示對該指令的最終結果無影響，但 Controller 仍提供確定的預設值。`im_w_en` 對所有指令均為 `0000`。

| 指令類別 | wb_en | ALU op1 | ALU op2 | next PC | JB 基底 | wb_data | 基本 dm_w_en |
| --- | --- | --- | --- | --- | --- | --- | --- |
| R-type | 1 | rs1 | rs2 | PC+4 | — | alu_out | 0000 |
| I-type ALU | 1 | rs1 | imm | PC+4 | — | alu_out | 0000 |
| Load | 1 | rs1 | imm | PC+4 | — | ld_data_f | 0000 |
| Store | 0 | rs1 | imm | PC+4 | — | 不寫回 | SB:0001／SH:0011／SW:1111 |
| Branch | 0 | rs1 | rs2 | jump ? jb_pc : PC+4 | PC | 不寫回 | 0000 |
| JAL | 1 | — | — | jb_pc | PC | pc_plus4 | 0000 |
| JALR | 1 | — | — | jb_pc，清 bit0 | rs1 | pc_plus4 | 0000 |
| LUI | 1 | — | imm | PC+4 | — | alu_out，直接傳 imm | 0000 |
| AUIPC | 1 | PC | imm | PC+4 | — | alu_out | 0000 |

`wb_en=1` 並不表示 x0 可寫：Top 以 `wb_en && rst` 接至 RegFile，RegFile 再以 `rd_index != 0` 保護 x0。`dm_w_en` 是尚未依 byte offset 位移的基本遮罩；SRAM 真正接收的是 `dm_mask`。

### Partial-access worked example

假設 SRAM 在對齊位址 `0x1000` 的 word 原值為 `0xAABBCCDD`，執行將 `0x1234` 寫入 `0x1001` 的 SH：

1. ALU 算出有效位址 `0x1001`。
2. `byte_offset=1`，`byte_shift=8`，`dm_address=0x1000`。
3. Controller 產生基本遮罩 `0011`；Top 左移後得到 `dm_mask=0110`。
4. rs2 的資料左移 8 bits，低 halfword 被放到目標 byte lanes；對此例 `dm_write_data=0x00123400`。
5. 上升緣只更新 byte1、byte2，新的 word 為 `0xAA1234DD`，其餘 byte 保持不變。
6. 若接著從 `0x1002` 執行 LB，Top 將 word 右移 16 bits，LD_Filter 取低 byte `0x12` 並符號延伸，得到 `0x00000012`。

此例是由程式邏輯推導的預期結果，不是額外執行的測試紀錄。Halfword offset 1 是題目要求支援的情況；跨 word 的存取不在本作業要求範圍。

### Single-cycle timing and reset

在兩個上升緣之間，IM 取指、Decoder、Imme_Ext、Controller、ALU、JB 與 load 路徑依目前 PC/暫存器狀態進行組合運算。下一個上升緣提交 `next_pc`，並在適當使能下寫入 RegFile 或 DM；這是單週期設計，不是五級管線。

PC 與 RegFile 的 `rst` 為低有效非同步 reset。SRAM 沒有 reset port；Top 以 `rst ? shifted_mask : 0` 防止 reset 期間意外 store。解除 reset 後，從 PC=0 取得指令。組合模組提供完整預設與各分支指派，避免產生不必要的 latch。

### Instruction examples

- ADDI：addi x5,x0,10。IM → Decoder/Imme_Ext → RegFile → ALU → wb_data → RegFile。預期：x5=10；next_pc=pc+4。
- LH at offset1：低16位資料需從 word 的 byte1 起讀。ALU 位址 → word 對齊 → DM → 右移8 → LH 符號延伸 → rd。預期：符號位取右移後 bit15；不跨 word。
- SH at offset1：rs2 低halfword=0x1234。mask0011<<1=0110；rs2<<8；上升緣只寫指定 lanes。預期：byte1=34、byte2=12，其餘保持。
- BEQ taken：PC=0x100、imm=-8、來源相等。ALU.jump=1 → Controller → JB 以PC加imm → next_pc。預期：next_pc=0xF8；不寫 rd。
- JAL：PC=0x100、imm=8。JB 算目標108；寫回另選pc_plus4。預期：rd=0x104；next_pc=0x108。

### Verification evidence

提供的完成版專案中，`build/Testing/Temporary/LastTest.log` 記錄以下七項本機測試通過：

| Test | Recorded result |
| --- | --- |
| print_test | PASS |
| msort_test | PASS |
| qsort_test | PASS |
| matmul_test | PASS |
| malloc_test_test | PASS |
| isa_edges_test | PASS |
| partial_access_test | PASS |

這些是隨專案保存的測試紀錄，不等同最終提交 commit 的正式評分。驗證目前 RTL 時，需先執行 `cmake --build build -j 4`，再執行 `ctest --test-dir build --output-on-failure --no-tests=error`。CrossVerify 逐指令比較 PC、32 個暫存器及記憶體存取相關狀態；預期完整成功訊息為 `100% tests passed, 0 tests failed out of 7`。


## Reflection Report (0 pts)

Please write a short reflection about the lab:

1. What did you learn from completing this assignment?
2. What challenges did you encounter, and how did you address them?
3. What feedback would you like to give the TAs about this lab?

### Your Reflection

#### 1. What did you learn from completing this assignment?

透過這次單週期 CPU 的實作，我理解到 RISC-V 指令的行為必須透過資料路徑與控制訊號共同完成。不同類型的指令可以共用 RegFile、ALU 與立即數產生器，但需要正確選擇運算元、寫回來源與下一個 PC。單週期設計中的取指、解碼、執行、必要的記憶體讀取及寫回準備都在同一週期內進行，而 PC 與暫存器等狀態在時脈邊緣更新。我也更清楚組合邏輯與時序邏輯的差別，以及非同步 reset、x0 保護與完整組合賦值的重要性。

#### 2. What challenges did you encounter, and how did you address them?

這份實作的關鍵挑戰是讓多種指令共用資料路徑時仍保持正確，尤其是部分記憶體存取與控制流。CPU 使用 byte address，但 SRAM 一次處理一個 32-bit word，因此我在 Top 中分別產生對齊位址、byte offset 與位移量，將 store 資料及 byte mask 一起左移，將 load 資料右移後再交給 LD_Filter 擴展。這樣能讓記憶體位置處理與符號延伸的責任清楚分開，也支援題目要求的 halfword offset 1。

另一個需要注意的地方是解碼欄位的意義會隨指令類型改變。例如 ADDI 的 bit30 屬於立即數，不能一律當成 SUB 控制；JALR 的目標需要清除 bit0，且 JAL/JALR 寫回的是 PC+4。我透過明確區分 opcode 類別、統一 Controller 與 Top 的 MUX 編碼，以及把跳轉目標與寫回路徑分開，處理這些情況。專案附帶的七項 PASS 紀錄可作為既有驗證證據；最終提交仍應對目前程式重新建置與測試。

#### 3. What feedback would you like to give the TAs about this lab?

逐指令 CrossVerify 與指令邊界、部分記憶體存取測試，有助於確認 CPU 不只是最後輸出正確，也能在中間每個步驟維持正確狀態。建議增加一組已知錯誤的示範，例如 byte mask 未位移或 JALR 目標處理錯誤，並搭配 mismatch 訊息與波形，示範如何從第一個差異追查到控制或資料路徑。若另附一張標示必要階層名稱與介面寬度的檢查表，也能幫助學生在整合前確認平台相容性。

