package com.example.gutenbergkit

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.util.Log
import org.wordpress.gutenberg.MediaUploadDelegate
import java.io.File
import java.io.IOException

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

        // Bake the EXIF orientation into the pixels. Re-encoding via compress()
        // writes no EXIF, so without this a portrait photo (stored landscape plus
        // an orientation tag) would upload rotated.
        val oriented = applyExifOrientation(scaled, file)

        val outputFile = File(file.parent, "resized-${file.name}")
        val format = if (mimeType == "image/png") Bitmap.CompressFormat.PNG
                     else Bitmap.CompressFormat.JPEG

        outputFile.outputStream().use { out ->
            oriented.compress(format, 85, out)
        }
        oriented.recycle()

        Log.d(TAG, "Resized image from ${width}×${height} to ${targetWidth}×${targetHeight}")
        return outputFile
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
