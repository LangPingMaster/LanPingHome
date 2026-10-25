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
