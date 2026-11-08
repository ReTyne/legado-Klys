package com.legado.md3

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

/**
 * MOBI HUFF/CDIC 解压 —— 纯 Kotlin 实现，逐字对齐 Sigma
 * `lib/mobi/decompress/HuffcdicDecompressor.kt` 的算法：
 *
 *  - HUFF 记录：magic/offset1/offset2，offset1 处 256 个 uint32 码长表 table1，
 *    offset2 处 32 组 (mincode, maxcode) 计算 mincodeTable/maxcodeTable；
 *  - CDIC 记录（可多个）：按 codeLength 取条目，每个条目含 2 字节 flag
 *    (bit15 = 已解压标志，低 15 位 = 长度) + 原始/二次压缩数据；
 *  - 解码：按位滑动窗口读 32 位 code，查 table1 得 codelen / maxcode，
 *    计算 CDIC 索引；未解压条目递归 decompress 后输出。
 *
 * 入参为 HUFF/CDIC 原始字节与压缩数据（由 Dart 侧解析 MOBI record 后传入），
 * 返回解压后的字节。全部使用 JDK（ByteBuffer/ByteArrayOutputStream），无新依赖。
 */
object MobiHuffDecompressor {

    class HuffException(message: String) : RuntimeException(message)

    private class Entry(var data: ByteArray, var decompressed: Boolean)

    fun decompress(huff: ByteArray, cdics: List<ByteArray>, data: ByteArray): ByteArray {
        val hb = ByteBuffer.wrap(huff)
        if (readString(hb, 0, 4) != "HUFF") throw HuffException("Invalid HUFF record")
        val offset1 = readU32(hb, 8)
        val offset2 = readU32(hb, 12)

        require(offset1 >= 0 && offset1 + 256 * 4 <= huff.size) { "HUFF offset1 out of range" }
        require(offset2 >= 0 && offset2 + 32 * 8 <= huff.size) { "HUFF offset2 out of range" }

        // HUFF 256 组码长表（大端 uint32）
        val table1 = IntArray(256) { i -> readU32(hb, offset1 + i * 4) }

        // 32 组 (mincode, maxcode)，按 Sigma 左移 (32 - i) 归一到 32 位空间
        val mincodeTable = LongArray(33)
        val maxcodeTable = LongArray(33)
        for (i in 1..32) {
            val base = offset2 + (i - 1) * 8
            val mincode = readU32(hb, base).toLong()
            val maxcode = readU32(hb, base + 4).toLong()
            mincodeTable[i] = mincode shl (32 - i)
            maxcodeTable[i] = ((maxcode + 1) shl (32 - i)) - 1
        }

        // CDIC 多字典，按位拼成同一 dictionary
        val dictionary = ArrayList<Entry>()
        for (rec in cdics) {
            val rb = ByteBuffer.wrap(rec)
            if (readString(rb, 0, 4) != "CDIC") throw HuffException("Invalid CDIC record")
            val length = readU32(rb, 4)
            val numEntries = readU32(rb, 8)
            val codeLength = readU32(rb, 12)
            if (codeLength < 0 || codeLength > 30) throw HuffException("Invalid CDIC codeLength")
            if (length < 0 || length >= rec.size) throw HuffException("Invalid CDIC length")
            val n = minOf(1 shl codeLength, numEntries - dictionary.size)
            for (j in 0 until n) {
                val off = readU16(rb, length + j * 2)
                if (off < 0 || length + off + 2 > rec.size) {
                    throw HuffException("CDIC offset out of range")
                }
                val x = readU16(rb, length + off)
                val len = x and 0x7fff
                val dec = (x and 0x8000) != 0
                if (length + off + 2 + len > rec.size) {
                    throw HuffException("CDIC entry out of range")
                }
                val bytes = ByteArray(len)
                System.arraycopy(rec, length + off + 2, bytes, 0, len)
                dictionary.add(Entry(bytes, dec))
            }
        }

        return decode(data, table1, mincodeTable, maxcodeTable, dictionary)
    }

    private fun decode(
        data: ByteArray,
        table1: IntArray,
        mincode: LongArray,
        maxcode: LongArray,
        dict: MutableList<Entry>,
    ): ByteArray {
        val bos = ByteArrayOutputStream()
        var bitsLeft = data.size * 8
        var pos = 0
        var x = readUx(data, pos, 8)
        var bitcount = 32

        while (true) {
            if (bitcount <= 0) {
                pos += 4
                x = readUx(data, pos, 8)
                bitcount += 32
            }

            val code = (x shr bitcount) and 0xFFFFFFFFL
            val t1 = table1[(code shr 24).toInt()]
            var codelen = t1 and 0x1f
            var maxc = (((t1.toLong() shr 8) + 1) shl (32 - codelen)) - 1

            if (t1 and 0x80 == 0) {
                while (codelen < 32 && code < mincode[codelen]) codelen++
                maxc = maxcode[codelen]
            }

            bitcount -= codelen
            bitsLeft -= codelen
            if (bitsLeft < 0) break

            val index = ((maxc - code) shr (32 - codelen)).toInt()
            if (index < 0 || index >= dict.size) {
                throw HuffException("CDIC index out of range: $index")
            }
            val entry = dict[index]
            if (!entry.decompressed) {
                entry.data = decode(entry.data, table1, mincode, maxcode, dict)
                entry.decompressed = true
            }
            bos.write(entry.data)
        }
        return bos.toByteArray()
    }

    /** 对齐 Sigma readUIntX：从 offset 起按大端读最多 maxlen 字节组装成 long */
    private fun readUx(b: ByteArray, offset: Int, maxlen: Int): Long {
        var value = 0L
        var i = maxlen
        var p = offset
        while (i-- > 0 && p < b.size) {
            value = value or ((b[p].toLong() and 0xFF) shl (i * 8))
            p++
        }
        return value
    }

    private fun readU32(bb: ByteBuffer, off: Int): Int = bb.getInt(off)

    private fun readU16(bb: ByteBuffer, off: Int): Int = bb.getShort(off).toInt() and 0xFFFF

    private fun readString(bb: ByteBuffer, off: Int, len: Int): String {
        if (off < 0 || off + len > bb.limit()) return ""
        val a = ByteArray(len)
        val saved = bb.position()
        bb.position(off)
        bb.get(a)
        bb.position(saved)
        return String(a, Charsets.US_ASCII)
    }
}
