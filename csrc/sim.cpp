#include <stdlib.h>
#include <iostream>
#include <verilated.h>
#ifdef TRACE_VCD
#include <verilated_vcd_c.h>
#else
#include <verilated_fst_c.h>
#endif
#include "VTEST_PLATFORM.h"
#include "VTEST_PLATFORM__Syms.h"
#include "memory.h"
#include <array>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iomanip>
#include "config.h"

namespace {

constexpr size_t PARAM_K = 16;
constexpr size_t PARAM_G = 30;
constexpr size_t PARAM_N1 = PARAM_K + PARAM_G;
constexpr size_t RM_CODEWORD_BYTES = 16;
constexpr size_t NUM_TESTS = 10;
constexpr size_t PARAM_M = 8;
constexpr std::array<uint16_t, 3> GF_REDUCTION_TAPS = {4, 3, 2};

constexpr std::array<uint8_t, PARAM_G> PARAM_RS_POLY = {
    89,  69,  153, 116, 176,
    117, 111, 75,  73,  233,
    242, 233, 65,  210, 21,
    139, 103, 173, 67,  118,
    105, 210, 174, 110, 74,
    69,  228, 82,  255, 181
};

constexpr std::array<std::array<uint8_t, PARAM_K>, NUM_TESTS> TEST_MSGS = {{
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
     0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},
    {0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
     0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff},
    {0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
     0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f},
    {0x0f, 0x0e, 0x0d, 0x0c, 0x0b, 0x0a, 0x09, 0x08,
     0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01, 0x00},
    {0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef,
     0xfe, 0xdc, 0xba, 0x98, 0x76, 0x54, 0x32, 0x10},
    {0xde, 0xad, 0xbe, 0xef, 0xca, 0xfe, 0xba, 0xbe,
     0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88},
    {0x7b, 0x3c, 0xa1, 0x09, 0xf0, 0x5e, 0xd2, 0x44,
     0x18, 0xc7, 0x91, 0x2a, 0x63, 0xbd, 0x06, 0xe8},
    {0x94, 0x12, 0xe3, 0x7f, 0x20, 0xd9, 0x4b, 0x6c,
     0xa5, 0x38, 0x01, 0xce, 0xfa, 0x57, 0x89, 0x2d},
    {0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01,
     0x7f, 0xbf, 0xdf, 0xef, 0xf7, 0xfb, 0xfd, 0xfe},
    {0x13, 0x57, 0x9b, 0xdf, 0x24, 0x68, 0xac, 0xe0,
     0x31, 0x75, 0xb9, 0xfd, 0x42, 0x86, 0xca, 0x0e},
}};

uint16_t gf_reduce(uint16_t x)
{
    uint64_t mod;
    const int reduction_steps = 2;
    const size_t gf_reduction_tap_count = GF_REDUCTION_TAPS.size();

    for (int i = 0; i < reduction_steps; ++i) {
        mod = x >> PARAM_M;
        x &= (1 << PARAM_M) - 1;
        x ^= mod;

        uint16_t z1 = 0;
        for (size_t j = gf_reduction_tap_count; j; --j) {
            uint16_t z2 = GF_REDUCTION_TAPS[j - 1];
            uint16_t dist = z2 - z1;
            mod <<= dist;
            x ^= mod;
            z1 = z2;
        }
    }

    return static_cast<uint16_t>(x);
}

void gf_carryless_mul(uint8_t c[2], uint8_t a, uint8_t b)
{
    uint16_t h = 0, l = 0, g = 0, u[4];
    uint32_t tmp1, tmp2;
    uint16_t mask;

    u[0] = 0;
    u[1] = b & 0x7f;
    u[2] = u[1] << 1;
    u[3] = u[2] ^ u[1];
    tmp1 = a & 3;

    for (size_t i = 0; i < 4; i++) {
        tmp2 = static_cast<uint32_t>(tmp1 - i);
        g ^= (u[i] & static_cast<uint32_t>(0 - (1 - ((tmp2 | (0 - tmp2)) >> 31))));
    }

    l = g;
    h = 0;

    for (size_t i = 2; i < 8; i += 2) {
        g = 0;
        tmp1 = (a >> i) & 3;
        for (size_t j = 0; j < 4; ++j) {
            tmp2 = static_cast<uint32_t>(tmp1 - j);
            g ^= (u[j] & static_cast<uint32_t>(0 - (1 - ((tmp2 | (0 - tmp2)) >> 31))));
        }

        l ^= g << i;
        h ^= g >> (8 - i);
    }

    mask = (-((b >> 7) & 1));
    l ^= ((a << 7) & mask);
    h ^= ((a >> 1) & mask);

    c[0] = static_cast<uint8_t>(l);
    c[1] = static_cast<uint8_t>(h);
}

uint16_t gf_mul(uint16_t a, uint16_t b)
{
    uint8_t c[2] = {0};
    gf_carryless_mul(c, static_cast<uint8_t>(a), static_cast<uint8_t>(b));
    uint16_t tmp = static_cast<uint16_t>(c[0] ^ (c[1] << 8));
    return gf_reduce(tmp);
}

void reed_solomon_encode(uint8_t *cdw, const uint8_t *msg)
{
    size_t i, j, k;
    uint8_t gate_value = 0;

    uint16_t tmp[PARAM_G] = {0};
    uint8_t msg_bytes[PARAM_K] = {0};
    uint8_t cdw_bytes[PARAM_N1] = {0};

    memcpy(msg_bytes, msg, PARAM_K);

    for (i = 0; i < PARAM_K; ++i) {
        gate_value = msg_bytes[PARAM_K - 1 - i] ^ cdw_bytes[PARAM_N1 - PARAM_K - 1];

        for (j = 0; j < PARAM_G; ++j) {
            tmp[j] = gf_mul(gate_value, PARAM_RS_POLY[j]);
        }

        for (k = PARAM_N1 - PARAM_K - 1; k; --k) {
            cdw_bytes[k] = cdw_bytes[k - 1] ^ tmp[k];
        }

        cdw_bytes[0] = tmp[0];
    }

    memcpy(cdw_bytes + PARAM_N1 - PARAM_K, msg_bytes, PARAM_K);
    memcpy(cdw, cdw_bytes, PARAM_N1);
}

void reed_muller_encode_byte(uint8_t *codeword, uint8_t message)
{
    int32_t first_word = -static_cast<int32_t>((message >> 7) & 1);
    uint32_t word[4] = {0};

    first_word ^= -static_cast<int32_t>((message >> 0) & 1) & 0xaaaaaaaa;
    first_word ^= -static_cast<int32_t>((message >> 1) & 1) & 0xcccccccc;
    first_word ^= -static_cast<int32_t>((message >> 2) & 1) & 0xf0f0f0f0;
    first_word ^= -static_cast<int32_t>((message >> 3) & 1) & 0xff00ff00;
    first_word ^= -static_cast<int32_t>((message >> 4) & 1) & 0xffff0000;

    word[0] = static_cast<uint32_t>(first_word);

    first_word ^= -static_cast<int32_t>((message >> 5) & 1);
    word[1] = static_cast<uint32_t>(first_word);
    first_word ^= -static_cast<int32_t>((message >> 6) & 1);
    word[3] = static_cast<uint32_t>(first_word);
    first_word ^= -static_cast<int32_t>((message >> 5) & 1);
    word[2] = static_cast<uint32_t>(first_word);

    for (size_t part = 0; part < 4; ++part) {
        for (size_t byte = 0; byte < 4; ++byte) {
            codeword[part * 4 + byte] =
                static_cast<uint8_t>((word[part] >> (8 * byte)) & 0xff);
        }
    }
}

void write_hex_byte(std::ofstream &out, uint8_t value)
{
    out << std::hex << std::setfill('0') << std::setw(2) << static_cast<unsigned>(value);
}

bool generate_encoder_golden_data()
{
    std::ofstream msg_file("encoder_msg.memh");
    std::ofstream code_file("encoder_rm.memh");

    if (!msg_file || !code_file) {
        std::cerr << "[ENC GEN] failed to open encoder_msg.memh or encoder_rm.memh\n";
        return false;
    }

    for (const auto &msg : TEST_MSGS) {
        uint8_t rs_codeword[PARAM_N1] = {0};
        reed_solomon_encode(rs_codeword, msg.data());

        for (int i = PARAM_K - 1; i >= 0; --i) {
            write_hex_byte(msg_file, msg[i]);
        }
        msg_file << '\n';

        for (size_t rs_idx = 0; rs_idx < PARAM_N1; ++rs_idx) {
            uint8_t rm_codeword[RM_CODEWORD_BYTES] = {0};
            size_t rs_byte_idx = PARAM_N1 - 1 - rs_idx;
            reed_muller_encode_byte(rm_codeword, rs_codeword[rs_byte_idx]);

            for (size_t byte = 0; byte < RM_CODEWORD_BYTES; ++byte) {
                write_hex_byte(code_file, rm_codeword[byte]);
            }
            code_file << '\n';
        }
    }

    std::cout << "[ENC GEN] generated " << NUM_TESTS
              << " full encoder golden vectors from C reference algorithms\n";
    return true;
}

} // namespace

#ifdef TRACE_ON
bool trace_on = true;
#else
bool trace_on = false;
#endif

vluint64_t sim_time = 0;

double sc_time_stamp()
{
    return sim_time;
}

VTEST_PLATFORM *dut = nullptr;
#ifdef TRACE_VCD
using TraceType = VerilatedVcdC;
const char *trace_file = "waveform.vcd";
#else
using TraceType = VerilatedFstC;
const char *trace_file = "waveform.fst";
#endif

TraceType *m_trace = nullptr;
void tick();
void runtill();

int main(int argc, char **argv, char **env)
{
    if (!generate_encoder_golden_data()) {
        exit(EXIT_FAILURE);
    }

    // 1. initialize verilator and create instance of the DUT
    dut = new VTEST_PLATFORM;
    Verilated::traceEverOn(true);
    m_trace = new TraceType;
    dut->trace(m_trace, 5);
    m_trace->open(trace_file);
    //=======================================================
    // 2. dut reset
    dut->rst_n = 0;
    tick();
    dut->rst_n = 1;
    //=======================================================
    // 3. main simulation loop
    tick();
    runtill();

    m_trace->close();
    delete dut;
    exit(EXIT_SUCCESS);
}

void tick()
{
    dut->clk = 0;
    dut->eval();
    if (trace_on && m_trace)
        m_trace->dump(sim_time);
    sim_time++;
    dut->clk = 1;
    dut->eval();
    if (trace_on && m_trace)
        m_trace->dump(sim_time);
    sim_time++;
}

void runtill()
{
    do
    {
        dut->clk ^= 1;
        dut->eval();
        if (trace_on && m_trace)
            m_trace->dump(sim_time);
        sim_time++;
    } while (!Verilated::gotFinish() && sim_time < MAX_SIM_TIME);
}
