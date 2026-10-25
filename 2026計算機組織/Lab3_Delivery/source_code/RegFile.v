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
