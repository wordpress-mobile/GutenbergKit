package com.example.gutenbergkit

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import org.wordpress.gutenberg.MediaUploadDelegate
import java.io.File

/**
 * Demo media upload delegate that resizes images to a maximum dimension of 2000px.
 *
 * Only overrides [processFile] — [uploadFile] returns null so the default uploader is used.
 */
class DemoMediaUploadDelegate : MediaUploadDelegate {
    companion object {
        private const val TAG = "DemoMediaUploadDelegate"
    }

    override suspend fun processFile(file: File, mimeType: String): File {
        if (!mimeType.startsWith("image/") || mimeType == "image/gif") {
            return file
        }

        val maxDimension = 2000

        val options = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        BitmapFactory.decodeFile(file.absolutePath, options)

        val width = options.outWidth
        val height = options.outHeight
        if (width <= 0 || height <= 0) return file

        val longestSide = maxOf(width, height)
        if (longestSide <= maxDimension) return file

        // Calculate sample size for memory-efficient decoding
        val sampleSize = Integer.highestOneBit(longestSide / maxDimension)
        val decodeOptions = BitmapFactory.Options().apply {
            inSampleSize = sampleSize
        }
        val sampled = BitmapFactory.decodeFile(file.absolutePath, decodeOptions) ?: return file

        // Scale to exact target dimensions
        val scale = maxDimension.toFloat() / longestSide.toFloat()
        val targetWidth = (width * scale).toInt()
        val targetHeight = (height * scale).toInt()
        val scaled = Bitmap.createScaledBitmap(sampled, targetWidth, targetHeight, true)
        if (scaled !== sampled) sampled.recycle()

        val outputFile = File(file.parent, "resized-${file.name}")
        val format = if (mimeType == "image/png") Bitmap.CompressFormat.PNG
                     else Bitmap.CompressFormat.JPEG

        outputFile.outputStream().use { out ->
            scaled.compress(format, 85, out)
        }
        scaled.recycle()

        Log.d(TAG, "Resized image from ${width}×${height} to ${targetWidth}×${targetHeight}")
        return outputFile
    }
}
