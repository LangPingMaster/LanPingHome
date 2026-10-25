# Lab 3 Assignment Report

## Student Information

Please enter your name and student ID below.

- Student Name: 彭靖翔
- Student ID: E24144773

You may answer in English or Traditional Chinese. Explain your own implementation and refer to its signal names where helpful.

## CPU Implementation (20 pts)

1. **CPU architecture diagram:** Draw a diagram of your single-cycle CPU showing its modules, main datapath connections, and control signals. You may draw it by hand or use draw.io. Include a clear image in this report.
2. **Module implementation:** Explain how you implemented each of the nine modules: Reg_PC, RegFile, Decoder, Imme_Ext, ALU, JB_Unit, LD_Filter, Controller, and Top. Describe the main logic of each module and how Top connects them to form the CPU.

### Your Answer

#### 一、設計目標、實作範圍與整體架構

本次作業依提供的介面完成 RV32I 單周期 CPU，主要作答位於 `rtl/src/` 的九個 Verilog 模組。CPU 支援 37 條指定指令，包含整數算術、邏輯、移位、比較、載入、儲存、條件分支、JAL、JALR、LUI 與 AUIPC。硬體本身不包含乘除法器、CSR、例外處理、快取或管線化機制；`matmul` 的乘法由 RV32I 工具鏈產生的軟體乘法程序執行。

本設計將工作分成「組合資料路徑」與「時序狀態」：在一個周期內，由目前 PC 取得指令，解碼後讀取來源暫存器、產生立即數，再計算 ALU 結果、記憶體位址或分支／跳躍目標；到時脈正緣才更新 PC、目的暫存器與需要寫入的資料記憶體。這些是同一周期內的資料相依步驟，不是五級管線，也不是每個步驟各占一個周期。

##### 1.1 CPU architecture diagram：整體架構圖

![圖一：單周期 CPU 模組、主要資料路徑與控制訊號](images/cpu_architecture.png)

圖一對應 `Top.v` 的實際連接，包含全部九個學生模組、提供的 IM／DM，以及實作在 Top 內的 MUX 與資料對位邏輯。藍色實線代表主要資料路徑，綠色虛線代表控制訊號，橘色線代表回寫／狀態回授。圖中部分操作數選擇與位移以 Top 邏輯方塊表示，並非額外的 Verilog 子模組。為避免總覽圖過度交叉，PC、rs1_data、imm、alu_out與pc_plus4的部分共用連線以同名訊號註記；完整連線另見詳細向量圖及控制表。

- `PC`、`regfile`、`IM`、`DM` 是測試平台直接存取的實例名稱，必須保留。
- 暫存器陣列名稱為 `regfile.registers`，PC 狀態為 `PC.current_pc`。
- `IM` 使用 `READ_ONLY=1`，`DM` 使用 `READ_ONLY=0`；`Top.halt` 直接接到 `DM.halt`。
- PC 與 RegFile 接收低有效非同步 reset；DM 沒有 reset 埠，因此由 Top 在 reset 期間將實際寫入 mask 清零。
- 圖中 `WB` 是 Top 內的組合選擇邏輯，不是額外的流水級。

[圖一 SVG 向量版本](images/cpu_architecture.svg)；[所有 MUX 與控制連線的詳細向量圖](images/cpu_architecture_detail.svg)。向量版本可放大查看個別訊號。

##### 1.2 指令支援範圍

| 類別 | 指令 | 數量 |
|---|---|---:|
| R-type | `add sub sll slt sltu xor srl sra or and` | 10 |
| I-type ALU | `addi slti sltiu xori ori andi slli srli srai` | 9 |
| Load | `lb lh lw lbu lhu` | 5 |
| Store | `sb sh sw` | 3 |
| Branch | `beq bne blt bge bltu bgeu` | 6 |
| Jump | `jal jalr` | 2 |
| U-type | `lui auipc` | 2 |
| 合計 | 指定 RV32I 子集 | **37** |

本作業使用 MMIO 儲存來輸出字元與結束程式，不以 ECALL／EBREAK 作為正常終止方式。測試中的 `.word 0` 是故意安排的失敗出口，不能把它加入合法指令來迴避測試失敗。

#### 二、九個模組的實作與設計原因

##### 2.1 Reg_PC：保存目前程式計數器

**介面與責任。** 輸入為 `clk`、`rst` 與 32-bit `next_pc`，輸出為 32-bit `current_pc`。此模組只保存 PC，不自行決定是否分支，也不自行加四。下一個 PC 的選擇全部由 Top 完成。

```verilog
always @(posedge clk or negedge rst) begin
    if (!rst) current_pc <= 32'b0;
    else current_pc <= next_pc;
end
```

**設計原因。** `negedge rst` 讓 reset 拉低時立即清零，無須等待正緣。時序更新使用非阻塞指派 `<=`，使所有暫存器以同一個正緣前的資料共同更新。

**例子。** 若目前 `pc=0x20`，一般指令的 `next_pc=0x24`，則下一個正緣後 `current_pc=0x24`；若分支成立，Top 改提供 `next_pc=0x1C`，本模組直接保存 `0x1C`。若本模組又額外加四，就會破壞 Top 已經選好的目標。

##### 2.2 RegFile：32 個通用暫存器與 x0 保護

**介面與責任。** `rs1_index`、`rs2_index` 為兩個 5-bit 讀取索引，對應 `rs1_data_out`、`rs2_data_out`。寫入端由 `wb_en`、`rd_index`、`wb_data` 控制。內部為 `reg [31:0] registers [0:31]`，共 32 個 32-bit 暫存器。

```verilog
reg [31:0] registers [0:31];
integer i;
always @(posedge clk or negedge rst) begin
    if (!rst) begin
        for (i = 0; i < 32; i = i + 1) registers[i] <= 32'b0;
    end else begin
        registers[0] <= 32'b0;
        if (wb_en && rd_index != 5'b0) registers[rd_index] <= wb_data;
    end
end
always @(*) begin
    rs1_data_out = (rs1_index == 0) ? 32'b0 : registers[rs1_index];
    rs2_data_out = (rs2_index == 0) ? 32'b0 : registers[rs2_index];
end
```

**設計原因。** 兩個讀埠是組合邏輯，可在同一周期提供兩個來源值；寫埠在正緣提交。x0 不只在讀取時強制為零，也拒絕寫入索引 0，讓平台觀察到的 `registers[0]` 本身也是零。Reset 將所有暫存器清零，包含 x2；stack pointer 的初值由 `runtime/src/start.S` 執行 `la sp, __stack_top` 設定，而不是在硬體中私自預設。

**例子一：x0。** `addi x0,x0,123` 即使使 `wb_en=1`，也因 `rd_index=0` 被忽略，x0 保持零。

**例子二：JALR 的來源與目的相同。** 對 `jalr x5,0(x5)`，假設舊 x5 為 `0x101`、PC 為 `0x20`，組合路徑先用舊 x5 算出目標 `0x100`，正緣再把 x5 寫成 link 值 `0x24`。非阻塞更新避免使用剛寫回的 x5 計算本條指令的目標。

##### 2.3 Decoder：固定欄位擷取

Decoder 是組合邏輯，將 32-bit `inst` 的欄位分別交給 Controller、RegFile 與其他模組。

| 輸出 | 擷取欄位 | 寬度 |
|---|---|---:|
| `dc_out_opcode` | `inst[6:2]` | 5 |
| `dc_out_func3` | `inst[14:12]` | 3 |
| `dc_out_func7` | `inst[30]` | 1 |
| `dc_out_rs1_index` | `inst[19:15]` | 5 |
| `dc_out_rs2_index` | `inst[24:20]` | 5 |
| `dc_out_rd_index` | `inst[11:7]` | 5 |

```verilog
always @(*) begin
    dc_out_opcode = inst[6:2];
    dc_out_func3 = inst[14:12];
    dc_out_func7 = inst[30];
    dc_out_rs1_index = inst[19:15];
    dc_out_rs2_index = inst[24:20];
    dc_out_rd_index = inst[11:7];
end
```

**重要介面差異。** 本作業的 opcode 不是完整的七位元，`func7` 也不是完整的 `inst[31:25]`，而只有 bit30。例如 ADDI 的五位 opcode 是 `00100`，不能拿完整七位 `0010011` 直接與這個介面比較。

**例子。** `0xFFF00293` 是 `addi x5,x0,-1`，解碼得到 opcode=`00100`、func3=`000`、func7=`1`、rs1=0、rd=5。此處 func7=1 是立即數位元造成的，並不代表 SUB；Controller／ALU 必須連同 opcode 判斷。

##### 2.4 Imme_Ext：立即數重組與符號延伸

此模組只接收 `inst`，自行用 `inst[6:2]` 選擇格式，沒有額外的 `ImmSel` 輸入。每次先給 `imm_ext_out=0` 的預設值，避免不完整賦值形成 latch。

| 格式 | 支援指令 | 重組方式與理由 |
|---|---|---|
| I | I-ALU、load、JALR | `inst[31:20]` 為 12-bit signed immediate，補 20 個符號位 |
| S | store | 接合 `inst[31:25]` 與 `inst[11:7]`，再符號延伸 |
| B | branch | 依 `{inst[31],inst[7],inst[30:25],inst[11:8],0}` 重組 13 bits |
| U | LUI、AUIPC | `inst[31:12]` 左移 12 bits，也就是低 12 bits 補零 |
| J | JAL | 依 `{inst[31],inst[19:12],inst[20],inst[30:21],0}` 重組 21 bits |

以下是實際使用的 B、U、J 格式核心敘述：

```verilog
5'b11000:
    imm_ext_out = {{19{inst[31]}}, inst[31], inst[7],
                   inst[30:25], inst[11:8], 1'b0};
5'b01101, 5'b00101:
    imm_ext_out = {inst[31:12], 12'b0};
5'b11011:
    imm_ext_out = {{11{inst[31]}}, inst[31], inst[19:12],
                   inst[20], inst[30:21], 1'b0};
```

**例子一。** I-type 立即數 `0xFFF` 的最高位為 1，延伸為 `0xFFFFFFFF`，代表 -1。

**例子二。** branch 位移 -4 經重組後為 `0xFFFFFFFC`；若目前 PC=`0x40`，成立時目標為 `0x3C`。最低位零已在立即數產生器補上，Top 不可再乘二。

**例子三。** `lui x8,0x80000` 的立即數輸出為 `0x80000000`，可作為 RAM 基底。`sltiu` 雖然使用 unsigned 比較，其 I-type 立即數仍必須先符號延伸，而非先零延伸。

##### 2.5 ALU：算術、邏輯、位址與分支比較

輸入為解碼後的 `opcode`、`func3`、`func7`，以及 Top 選好的 `operand1`、`operand2`；輸出為 32-bit `alu_out` 與 1-bit `jump`。

**預設值與運算分類。** 每次組合計算先將 `alu_out=0`、`jump=0`。R-type 與 I-type ALU 依 func3 選擇運算；load/store/AUIPC 使用加法；LUI 直接輸出 operand2；branch 只設定 jump，不用 alu_out 當目標位址。

```verilog
3'b000: alu_out = (opcode == 5'b01100 && func7)
                   ? operand1 - operand2 : operand1 + operand2;
3'b001: alu_out = operand1 << operand2[4:0];
3'b010: alu_out = {31'b0, ($signed(operand1) < $signed(operand2))};
3'b011: alu_out = {31'b0, (operand1 < operand2)};
3'b101: begin
    if (func7) alu_out = $signed(operand1) >>> operand2[4:0];
    else alu_out = operand1 >> operand2[4:0];
end
```

1. **ADD、SUB 與 ADDI。** 只有 R-type 且 func7=1 才選減法。對 `addi x5,x6,-1`，立即數會讓 bit30=1，但仍應做加法，不能誤判為 SUB。
2. **移位量。** RV32 只使用 operand2 的低五位，所以移位量 34 等同 2。SRA／SRAI 先使用 `$signed(operand1)`，再套用 `>>>` 才能補符號位。
3. **比較結果。** SLT／SLTU 只產生布林 0 或 1，顯式補成 32 bits；BLT／BGE 使用 signed，BLTU／BGEU 使用 unsigned。
4. **32-bit 算術。** 加減超出 32 bits 時保留低 32 bits，符合本次整數指令的位元結果；未實作溢位例外。

| 輸入／操作 | 預期結果 | 說明 |
|---|---|---|
| `5 + 0xFFFFFFFF` | `0x00000004` | ADDI -1 仍為加法 |
| `0xFFFFFFF0` 算術右移 34 | `0xFFFFFFFC`，即 -4 | 只取移位量低五位=2 |
| `0xFFFFFFF0` 邏輯右移 34 | `0x3FFFFFFC` | 高位補零 |
| signed `0xFFFFFFFF < 1` | 1 | -1 < 1 |
| unsigned `0xFFFFFFFF < 1` | 0 | 4294967295 不小於 1 |

分支比較由 jump 表示，對應如下：BEQ 為相等、BNE 為不等、BLT／BGE 為 signed 小於／大於等於、BLTU／BGEU 為 unsigned 小於／大於等於。Controller 再根據 jump 決定 next_pc_sel。

##### 2.6 JB_Unit：目標位址加法器

```verilog
always @(*) begin
    jb_out = operand1 + operand2;
end
```

JB_Unit 只接收兩個 32-bit operand 並輸出相加結果。Top 讓 operand2 固定為 imm；branch／JAL 的 operand1 是目前 PC，JALR 的 operand1 是 rs1。這樣可以將「目標計算」和「branch 是否成立」分開，避免把 branch 的比較結果與位址加法混在同一個 ALU 輸出。

**例子。** PC=`0x20`、branch imm=12 時，JB 算出 `0x2C`；若 jump=0，這個值雖然存在，Top 仍選 `0x24`。對 JALR，rs1=`0x101`、imm=0 時，JB 先產生 `0x101`，Top 再清 bit0 成為 `0x100`。清 bit0 不等於無條件清低兩位，測試平台仍要求實際執行的指令 PC 四位元組對齊。

##### 2.7 LD_Filter：載入結果的符號／零延伸

`LD_Filter` 不接位址，而接收 Top 已右移對位後的 `ld_data`；它只負責按照 func3 決定寬度與延伸方式。

```verilog
case (func3)
    3'b000: ld_data_f = {{24{ld_data[7]}}, ld_data[7:0]};
    3'b001: ld_data_f = {{16{ld_data[15]}}, ld_data[15:0]};
    3'b010: ld_data_f = ld_data;
    3'b100: ld_data_f = {24'b0, ld_data[7:0]};
    3'b101: ld_data_f = {16'b0, ld_data[15:0]};
    default: ld_data_f = 32'b0;
endcase
```

| 指令 | 擷取範圍 | 高位處理 | 例子 |
|---|---|---|---|
| LB | 低 8 bits | 複製 bit7 | 0x80 → 0xFFFFFF80，-128 |
| LBU | 低 8 bits | 補零 | 0x80 → 0x00000080，128 |
| LH | 低 16 bits | 複製 bit15 | 0x8000 → 0xFFFF8000，-32768 |
| LHU | 低 16 bits | 補零 | 0x8000 → 0x00008000，32768 |
| LW | 全部 32 bits | 原樣傳遞 | 0x89ABCDEF 不變 |

**設計關鍵。** 必須先在 Top 選出位址對應的 byte／halfword，再判斷新的 bit7／bit15。若直接對 SRAM 原始 word 延伸，offset 不為零時會拿到錯誤的資料或符號位。

##### 2.8 Controller：完整組合控制與安全預設

Controller 接收 `opcode`、`func3`、`func7`、`jump`，輸出下一個 PC 選擇、寫回使能、操作數選擇及記憶體寫入 mask。每次先設定全部預設值：不寫 IM、不寫 DM、不寫 rd、PC 選 PC+4，然後在各個合法指令類別中設定需要的控制值。這避免 latch，也使非 store 指令不會殘留上一條指令的 mask。

本設計的 MUX 編碼如下，Controller 與 Top 必須一致：

| 訊號 | 0 | 1 |
|---|---|---|
| `next_pc_sel` | PC+4 | branch／jump 目標 |
| `jb_op1_sel` | PC | rs1 |
| `alu_op1_sel` | rs1 | PC |
| `alu_op2_sel` | rs2 | imm |
| `wb_sel` | 非 load 路徑 | LD_Filter 結果 |

`alu_opcode=opcode`、`alu_func3=func3`、`alu_func7=func7` 原樣轉送。`im_w_en` 永遠為 `0000`。Store 基本 mask 依 func3 為 SB=`0001`、SH=`0011`、SW=`1111`；在 Controller 這一層還沒有依位址 offset 平移。

```verilog
5'b11000: next_pc_sel = jump;
5'b11011: begin wb_en = 1'b1; next_pc_sel = 1'b1; end
5'b11001: begin
    wb_en = 1'b1; next_pc_sel = 1'b1; jb_op1_sel = 1'b1;
end
```

| 類別 | ALU op1 | ALU op2 | 回寫 | 下一個 PC | DM 基本 mask |
|---|---|---|---|---|---|
| R-type | rs1 | rs2 | ALU | PC+4 | 0000 |
| I-ALU | rs1 | imm | ALU | PC+4 | 0000 |
| Load | rs1 | imm | LD_Filter | PC+4 | 0000 |
| Store | rs1 | imm | 不寫 rd | PC+4 | 0001／0011／1111 |
| Branch | rs1 | rs2 | 不寫 rd | jump 成立才選 PC+imm | 0000 |
| JAL | 不使用 ALU 結果 | 不使用 | PC+4 | PC+imm | 0000 |
| JALR | 不使用 ALU 結果 | 不使用 | PC+4 | (rs1+imm)&~1 | 0000 |
| LUI | rs1，但 ALU 忽略它 | imm | imm | PC+4 | 0000 |
| AUIPC | PC | imm | PC+imm | PC+4 | 0000 |

**例子。** `sh x5,1(x8)` 時，Controller 給 `alu_op2_sel=1`、`wb_en=0`、`dm_w_en=0011`。Top 看到有效位址 offset=1，才把實際 DM mask 變成 `0110`。另一方面，`wb_sel` 只有一位，不能單獨表達 ALU、load、PC+4 三個來源；因此 Top 在非 load 路徑再識別 JAL／JALR。

##### 2.9 Top：模組整合與最終資料路徑

Top 宣告所有中間訊號並實例化九個模組中其餘八個，以及兩個提供的 SRAM。Top 本身是第九個學生模組。重要資料路徑如下。

**（1）取指與下一個 PC。**

```verilog
assign pc_plus4 = pc + 32'd4;
assign next_pc = next_pc_sel ? jb_pc : pc_plus4;
assign jb_operand1 = jb_op1_sel ? rs1_data : pc;
assign jb_pc = (opcode == 5'b11001)
                 ? {jb_out[31:1], 1'b0} : jb_out;
```

一般指令選 PC+4，branch 成立或 JAL／JALR 選目標；只有 JALR 清 bit0。JAL／JALR 的 link 值另由 PC+4 產生，不與目標值混用。

**（2）ALU 操作數。**

```verilog
assign alu_operand1 = alu_op1_sel ? pc : rs1_data;
assign alu_operand2 = alu_op2_sel ? imm : rs2_data;
```

例如 AUIPC 選 PC＋imm，R-type 選 rs1＋rs2 的相應運算，load/store 選 rs1＋imm 計算有效位址。

**（3）寫回選擇。**

```verilog
assign wb_data = wb_sel ? ld_data_f :
                 ((opcode == 5'b11011 || opcode == 5'b11001)
                     ? pc_plus4 : alu_out);
```

Load 選 `ld_data_f`；JAL／JALR 選 `pc_plus4`；其餘寫 rd 的指令選 `alu_out`。Store 與 branch 的 wb_en 為零。RegFile 的實際寫入使能再以 `wb_en && rst` 保護 reset。

**（4）部分記憶體存取。**

```verilog
assign byte_offset = alu_out[1:0];
assign byte_shift = {byte_offset, 3'b000};
assign dm_address = {alu_out[31:2], 2'b00};
assign dm_write_data = rs2_data << byte_shift;
assign dm_mask = rst ? (dm_w_en << byte_offset) : 4'b0000;
assign ld_data = dm_read_data >> byte_shift;
```

`byte_shift` 等於 offset×8，值為 0、8、16 或 24。給 SRAM 的位址向下對齊到 4-byte word，但原本低兩位先保留於 `byte_offset`。Store 的資料與 mask 一起左移，load 的讀回資料先右移，再交給 LD_Filter。題目保證存取不跨 word，因此不需第二次讀取或跨 word 合併；不能自行把所有 halfword 位址強制對齊成偶數，因為測試包含 offset=1 的 SH／LH。

#### 三、Little-endian、部分讀寫與 MMIO 的完整範例

![圖二：部分讀寫的位址對齊、byte lane 與符號延伸](images/partial_access.png)

##### 3.1 SH offset=1：為什麼 mask 是 0110？

假設 RAM 原始 word=`0x55555555`、有效位址=`0x80000001`、rs2=`0x89ABCDEF`，執行 SH：

1. ALU 計算有效位址，Top 得到 offset=1、byte_shift=8。
2. `DM.address=0x80000000`，仍讀寫同一個對齊 word。
3. Controller 基本 mask=`0011`，Top 平移後 `dm_mask=0110`。
4. `dm_write_data=0x89ABCDEF<<8=0xABCDEF00`；SH 只寫 mask 選到的 lane1／lane2。
5. 低位址 lane0 與高位址 lane3 保持 0x55，結果為 `0x55CDEF55`。

| byte lane | 位址 | 原值 | 寫入使能 | 最後值 |
|---|---|---|---|---|
| lane0 | 0x80000000 | 55 | 0 | 55 |
| lane1 | 0x80000001 | 55 | 1 | EF |
| lane2 | 0x80000002 | 55 | 1 | CD |
| lane3 | 0x80000003 | 55 | 0 | 55 |

Hex word 的印法由高位到低位是 `55 CD EF 55`，而依位址由低到高的 byte 順序是 `55 EF CD 55`。這兩個觀察次序不同，但表示相同的小端資料。

##### 3.2 LH 與 LHU：先對位，再決定符號

若 `DM.read_data=0x00800000`、offset=1，Top 右移 8 bits 得 `ld_data=0x00008000`。LH 取低 16 bits 並複製 bit15，得到 `0xFFFF8000`（-32768）；LHU 補零，得到 `0x00008000`（32768）。這是 `partial_access.S` 明確涵蓋的情境。

##### 3.3 MMIO 字元輸出與正常 halt

| 功能 | CPU 有效 byte 位址 | 傳給 SRAM 的對齊位址 | mask | 有效資料 |
|---|---|---|---|---|
| 文字輸出 | 0xFFFFFFF7 | 0xFFFFFFF4 | 1000 | `write_data[31:24]` |
| 程式結束 | 0xFFFFFFFB | 0xFFFFFFF8 | 1000 | `write_data[24]` |

例如 `sb` 將數值 1 寫到 `0xFFFFFFFB`，offset=3，因此 `dm_write_data=0x01000000`、mask=`1000`。SRAM 在正緣將 halt 設成 `write_data[24]=1`，再由 `DM.halt` 傳到 `Top.halt`。若沒有平移 mask 或資料，程式可能無法停止。

#### 四、典型指令如何走完整個 CPU

| 指令與條件 | 資料路徑 | 正緣後的狀態 |
|---|---|---|
| `addi x5,x6,-1`，x6=5 | Decoder→RegFile→Imme_Ext→ALU 加法→WB | x5=4；PC+4 |
| `lw x5,4(x8)`，x8=0x80000000 | ALU 位址0x80000004→DM→LD_Filter→WB | x5=該word；PC+4 |
| `bne x7,x0,-4`，x7=2，PC=0x40 | ALU比較不等→jump=1；JB算0x3C | PC=0x3C；不寫rd |
| 同條BNE但x7=0 | jump=0，忽略JB結果 | PC=0x44；不寫rd |
| `jal x1,+8`，PC=0x20 | JB目標0x28；WB選PC+4 | x1=0x24；PC=0x28 |
| `jalr x5,0(x5)`，舊x5=0x101，PC=0x20 | 舊rs1+imm→清bit0；WB選PC+4 | PC=0x100；x5=0x24 |
| `auipc x22,0x12345`，PC=0x80 | ALU選PC+0x12345000 | x22=0x12345080；PC=0x84 |

#### 五、驗證方法、測試結果與輸出剖析

##### 5.1 建置與執行方式

在課程容器的個人 repository 根目錄執行：

```bash
cmake -S . -B build
cmake --build build -j2
ctest --test-dir build --output-on-failure
```

CMake 將九個 RTL 模組、SRAM 與 `CrossVerify.sv` 交給 Verilator 產生 C++ 模型，再和 `sim_main.cpp`、DPI 橋接 `CrossVerify.cpp`、參考 ISS 連結為 `verilator_sim`。另一方面，RISC-V 工具鏈用 `-march=rv32i -mabi=ilp32` 產生測試 ELF 與 `.hex`；ELF 供 ISS 使用，hex 供 RTL SRAM 載入。

本次操作紀錄的工具版本為 CMake 3.28.3、Verilator 5.038、riscv32-unknown-elf-gcc 15.1.0。CMake 對部分編譯器旗標探測顯示 Failed，不等於最終建置失敗；這次紀錄後續有 `Configuring done`、`Generating done`、`Built target verilator_sim`，且七項 CTest 通過。

##### 5.2 CrossVerify 如何確認正確性

1. 將同一個程式載入 RTL 與 ISS，reset 後先確認初始 PC 與 32 個 GPR 一致。
2. 在目前指令尚未提交前，記下 `executing_pc` 與 `executing_inst`，檢查指令位址及合法指令集合。
3. 對 load/store，獨立計算預期有效位址與對齊位址；對 store 檢查 byte-enable mask 與被選取的資料 bytes，也確認 IM 不被寫入。
4. `CrossVerify_step()` 呼叫 `ISS_step(ref_iss,1)`，使參考模型執行同一條指令。
5. 等待 RTL 的時脈正緣及 `#1ns`，讓 nonblocking 更新完成，再比較 `PC.current_pc` 與 `regfile.registers[0:31]`。
6. 若本條指令寫入 RAM，再讀回被寫的整個對齊 word，與 ISS 的 RAM 比較，確認相鄰未選取 bytes 沒有被破壞。
7. 比較 DUT 與 ISS 的 halt 狀態；到正常結束才印出 `Simulation PASS`，否則因不一致、非法指令或逾時而失敗。

這種驗證方式可以定位第一條產生差異的指令，比只觀察最終 printf 更精確。但它仍屬已提供測資的動態驗證，不等於窮舉所有輸入的形式驗證。

##### 5.3 本次附件的實際結果

以下取自新 ZIP 的 `build/Testing/Temporary/LastTest.log`，時間為 Oct 22 16:08 CST。指令數會受到編譯器與產生的機器碼影響，不應直接用來比較不同環境的 CPU 速度。

| 測試 | 結果 | 執行指令數 | 約耗時 | 驗證重點 |
|---|---|---:|---:|---|
| print_test | PASS | 1106 | 0.02s | C runtime、函式呼叫、字元MMIO |
| msort_test | PASS | 1848 | 0.02s | 遞迴、stack、有號比較、合併排序 |
| qsort_test | PASS | 4856 | 0.05s | 分割、交換、遞迴、輸出 |
| matmul_test | PASS | 2991 | 0.03s | 多層迴圈、陣列、軟體乘法 |
| malloc_test_test | PASS | 3731 | 0.04s | heap、配置對齊、load/store |
| isa_edges_test | PASS | 74 | 0.01s | x0、移位、符號、分支、JALR |
| partial_access_test | PASS | 142 | 0.01s | byte/halfword各offset、lane保護 |

貼上的 CTest 摘要為：

```text
100% tests passed, 0 tests failed out of 7
Total Test time (real) = 0.19 sec
```

各項秒數是四捨五入的顯示值，不必與總耗時相加完全相等。此表表示本機提供測資全通過，不宣稱已取得 GitHub 正式分數；報告20分仍由人工審閱。

##### 5.4 演算法結果與可見輸出

- **msort：** 測試陣列 `[9,-3,0,9,2,-8,1,4]` 應成為 `[-8,-3,0,1,2,4,9,9]`。程式以 expected 陣列逐項比較，不會列印排序陣列；錯誤會執行 `.word 0`，因此正常走到 PASS 具有自我檢查的意義。
- **qsort：** 原始陣列為 `10 7 8 9 1 5`，排序後為 `1 5 7 8 9 10`；此測試會印出陣列，且每步狀態同時接受 ISS 比對。
- **matmul：** 預期矩陣為 `[[-10,10,-2],[2,24,13],[4,2,5]]`。例如第一格為 `1×2+(-2)×3+3×(-2)=-10`。程式逐格比較，不額外列印矩陣。
- **malloc：** 第一個配置值依序為 5、10，第二個為15、20，之後列印釋放訊息。上游 allocator 的已知對齊修正由附件原有 `PatchRuntime.cmake` 在 build tree 產生副本完成，學生 RTL 沒有修改 runtime。

**文字重複的原因。** print 的整合輸出出現 `HHeelllloo,,  WWoorrlldd  112233`，原因是參考 ISS 的 `text_buffer.c` 會呼叫 printf，而 RTL 的 `SRAM.v` 在對應 MMIO store 也會 `$write`，所以兩側字元交錯。這個平台中的重複文字不能直接解讀為 RTL 把同一條指令提交兩次；仍應檢查逐指令狀態與 PASS。也不能把任何平台的重複輸出一律當正常。

##### 5.5 波形產生與分析

```bash
./build/verilator_sim +prog_elf_path="$PWD/build/tests/partial_access.elf" +trace
gtkwave waveform.fst
```

本次追蹤執行的終端輸出為：

```text
Simulation PASS: 142 instructions
- src/CrossVerify.sv:138: Verilog $finish
```

建議先加入 `clk`、`rst`、`PC.current_pc`、`inst`、`halt`，再依問題加入 `alu_out`、`jump`、`next_pc_sel`、`jb_pc`、`dm_address`、`dm_mask`、`dm_write_data`、`ld_data` 與 `ld_data_f`。觀察正緣前的輸入／組合結果，以及正緣後的 PC、rd、RAM 更新，才能區分計算錯誤與提交錯誤。

操作紀錄中的 GTKWave 截圖雖顯示整體 To=1426ns，畫面實際放大到最初約0–6ps。平台時脈每5ns反轉、周期10ns，所以這個極小時間窗不會呈現正常執行正緣；應先縮放至完整範圍再選取分析區間。1426ns 還包含初始化與觀察延遲，不能用來宣稱硬體最高工作頻率。

#### 六、設計正確性、限制與提交一致性

1. **避免 latch：** 組合模組使用 `always @(*)`，在所有輸出路徑給出完整賦值或預設值；PC／RegFile 使用正緣與非阻塞更新。
2. **控制一致：** Controller 與 Top 共用同一組 MUX 編碼；branch 的 jump 與目標加法分開處理。
3. **記憶體保護：** IM 永遠不寫；非store與reset期間的DM mask為零；store只改mask指定的bytes。
4. **介面相容：** 保留PC、regfile、IM、DM及registers名稱，讓提供的平台能直接觀察架構狀態。
5. **測試平台未改動：** 九個RTL是主要實作；未透過修改SRAM、CrossVerify、測試或參考模型來掩蓋差異。附件既有PatchISS／PatchRuntime由原始CMake使用，與學生新增修改應區分。
6. **題目範圍：** 僅處理保證不跨word的存取，未實作跨word合併、非法指令例外、pipeline hazard或cache；單周期設計沒有管線資料轉送／stall控制。
7. **完成程度：** 目前證據支持提供的七項本機測試全通過；提交時仍須讓report與實際RTL版本一致，並查看推送到預設分支的對應commit正式結果。

本次報告中的程式片段均依實際九個模組擷取；長模組僅引用關鍵區段，完整程式保留於 `rtl/src/`，避免報告與原始檔出現兩套不同實作。

## Reflection Report (0 pts)

Please write a short reflection about the lab:

1. What did you learn from completing this assignment?
2. What challenges did you encounter, and how did you address them?
3. What feedback would you like to give the TAs about this lab?

### Your Reflection

#### 一、從這次作業學到的內容

這次作業讓我把指令格式、控制訊號、資料路徑與架構狀態的關係連接起來。只會計算某條指令的結果，還不足以完成CPU；必須同時決定來源操作數、下一個PC、目的暫存器，以及哪些記憶體byte可被修改。例如JALR一方面要用舊rs1加立即數決定目標、清除bit0，另一方面又要把PC+4寫入rd；這讓我更清楚理解組合計算與正緣提交的差別。

我也學到相同位元樣式不等於相同數值解讀。`0xFFFFFFFF`在signed比較時是-1，在unsigned比較時是4294967295；`0x80`經LB與LBU會產生不同的32-bit結果。這些差異不是顯示格式而已，會直接影響ALU比較、branch控制與load回寫。

另一個重要收穫是分清「有效位址」、「對齊word位址」及「byte offset」。在部分讀寫中，只把位址對齊還不夠，必須保留offset，讓store的資料與mask一起移位，或讓load先移位再延伸。透過SH offset=1與LB/LBU的範例，可以具體檢查自己是否真正理解little-endian。

驗證方面，我學到編譯成功只代表語法與連結條件成立，不能代表CPU正確。CrossVerify能在每條指令提交後比較PC、所有GPR及必要的RAM內容，協助把錯誤定位到第一個差異，而不是等整個程式結束才猜測原因。這也讓我更重視可重現的測試紀錄與版本一致性。

#### 二、遇到的問題與處理方式

**1. Windows、WSL與容器是不同環境。** 操作紀錄一開始在WSL執行docker時出現「command could not be found」，需要先啟動Docker Desktop並啟用對應Ubuntu的WSL Integration。之後先檢查Docker連線，再使用課程的create／attach腳本進入容器；編譯與測試則在容器中的repository執行。我也確認Windows的`E:\...`、WSL的`/mnt/e/...`與容器的`/home/ubuntu/workspace/...`不能直接混用。

**2. 自訂SSH key沒有自動被選取。** 雖然已產生key，第一次clone仍出現`Permission denied (publickey)`。在SSH設定中指定該key的`IdentityFile`並啟用`IdentitiesOnly yes`後，再以`ssh -T git@github.com`確認成功驗證，才重新clone個人作業。這讓我理解「有產生key」和「Git實際使用正確key」是兩件事；公鑰可以登錄GitHub，私鑰不能加入repository。

**3. 子模組指令的執行目錄。** 在`~/workspace`直接執行`git submodule update`會出現`not a git repository`，因為該位置只是多個專案的上層資料夾。先進入`fall-2026-lab3-e24144773`根目錄後再操作，才是正確做法。Windows、WSL與容器的Git設定也可能不同，因此應在實際commit的環境確認設定；`user.name`不是SSH登入認證。

**4. RTL設計需要特別釐清的邊界條件。** 我在檢查實作時，將x0不可寫、ADDI不能因bit30=1而變成SUB、SRA需要signed左操作數、移位量只取低五位、JALR使用舊rs1及正確清bit0，列為重點。這些是程式正確性檢查項目；本報告不把未出現在紀錄中的錯誤宣稱為曾實際發生的故障。對部分讀寫，則用已提供的`partial_access.S`觀察不同offset及相鄰bytes保留，最後以原始CTest結果確認。

**5. 波形時間尺度與輸出文字的判讀。** GTKWave載入成功後，如果只顯示最初幾個ps，就算訊號看起來不變，也不能推論CPU沒有執行；需要先縮放到完整ns區間，再加入clk、rst、PC及相關資料路徑訊號。終端文字重複也要結合平台原碼判斷，因為ISS與RTL都會列印同一個MMIO字元。我因此學到先理解觀察工具和平台機制，再解釋畫面現象。

#### 三、給助教的建議

1. 建議在講義集中列出Windows、WSL與容器各自執行的指令，並在clone後明確提醒先`cd`進repository，再初始化submodules。對第一次使用Docker與SSH的同學，這可降低與CPU邏輯無關的環境除錯時間。
2. 建議提供一張完整的控制訊號編碼表，以及一個SH offset=1和一個JALR rd=rs1的逐步例子。這兩個例子能同時涵蓋資料對位、控制選擇和正緣更新的觀念。
3. 建議隨附GTKWave基本操作與建議訊號清單，特別說明Zoom Fit、十六進位顯示、正緣前後的觀察方式，以及參考ISS與RTL可能造成的雙重字元輸出。
4. 建議維持目前逐指令比對和部分讀寫測試，並在錯誤訊息旁提供「先觀察哪個訊號」的提示。這能引導學生修正第一個差異，而不是反覆push或修改測試平台來迴避失敗。
