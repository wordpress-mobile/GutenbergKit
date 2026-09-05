package com.example.gutenbergkit

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.util.Log
import org.wordpress.gutenberg.MediaProcessor
import org.wordpress.gutenberg.ProcessedProxyFile
import java.io.File
import java.io.IOException

/**
 * Demo media upload delegate that resizes images to a maximum dimension of 2000px.
 *
 * Only transforms the file; GutenbergKit performs the upload.
 */
class DemoMediaProcessor : MediaProcessor {
    companion object {
        private const val TAG = "DemoMediaProcessor"
    }

    // Only non-GIF images are ever resized (see processFile), so decline
    // everything else by metadata — the server then skips copying a file this
    // delegate would only pass through.
    override fun handlesFile(mimeType: String, filename: String): Boolean {
        return mimeType.startsWith("image/") && mimeType != "image/gif"
    }

    override suspend fun processFile(file: File, mimeType: String, filename: String): ProcessedProxyFile {
        if (!mimeType.startsWith("image/") || mimeType == "image/gif") {
            return ProcessedProxyFile.Original
        }

        val maxDimension = 2000

        val options = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        BitmapFactory.decodeFile(file.absolutePath, options)

        val width = options.outWidth
        val height = options.outHeight
        if (width <= 0 || height <= 0) return ProcessedProxyFile.Original

        val longestSide = maxOf(width, height)
        if (longestSide <= maxDimension) return ProcessedProxyFile.Original

        // Calculate sample size for memory-efficient decoding
        val sampleSize = Integer.highestOneBit(longestSide / maxDimension)
        val decodeOptions = BitmapFactory.Options().apply {
            inSampleSize = sampleSize
        }
        val sampled = BitmapFactory.decodeFile(file.absolutePath, decodeOptions) ?: return ProcessedProxyFile.Original

        // Scale to exact target dimensions
        val scale = maxDimension.toFloat() / longestSide.toFloat()
        val targetWidth = (width * scale).toInt()
        val targetHeight = (height * scale).toInt()
        val scaled = Bitmap.createScaledBitmap(sampled, targetWidth, targetHeight, true)
        if (scaled !== sampled) sampled.recycle()

        // Bake the EXIF orientation into the pixels. Re-encoding via compress()
        // writes no EXIF, so without this a portrait photo (stored landscape plus
        // an orientation tag) would upload rotated.
        val oriented = applyExifOrientation(scaled, file)

        // Re-encoding normalizes everything but PNG to JPEG (Bitmap.compress can't
        // round-trip WebP/HEIC/etc.), so report the ACTUAL output type and extension.
        // Otherwise a WebP/HEIC upload would be JPEG bytes labeled image/webp, and
        // WordPress would reject the content/extension mismatch.
        val (format, outputMimeType, outputExtension) =
            if (mimeType == "image/png") {
                Triple(Bitmap.CompressFormat.PNG, "image/png", "png")
            } else {
                Triple(Bitmap.CompressFormat.JPEG, "image/jpeg", "jpg")
            }

        val outputFile = File(file.parent, "resized-${file.name}")
        outputFile.outputStream().use { out ->
            oriented.compress(format, 85, out)
        }
        oriented.recycle()

        val outputFilename = filename.substringBeforeLast('.', filename) + ".$outputExtension"
        Log.d(TAG, "Resized image from ${width}×${height} to ${targetWidth}×${targetHeight}")
        return ProcessedProxyFile.Processed(outputFile, outputMimeType, outputFilename)
    }

    private fun applyExifOrientation(bitmap: Bitmap, sourceFile: File): Bitmap {
        val orientation = try {
            ExifInterface(sourceFile.absolutePath).getAttributeInt(
                ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL
            )
        } catch (e: IOException) {
            Log.w(TAG, "Failed to read EXIF orientation", e)
            ExifInterface.ORIENTATION_NORMAL
        }

        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> matrix.apply { postRotate(90f); postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_TRANSVERSE -> matrix.apply { postRotate(270f); postScale(-1f, 1f) }
            else -> return bitmap
        }

        val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        if (rotated !== bitmap) bitmap.recycle()
        return rotated
    }
}
