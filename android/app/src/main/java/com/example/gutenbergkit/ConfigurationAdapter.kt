package com.example.gutenbergkit

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView

class ConfigurationAdapter(
    private val items: List<ConfigurationItem>,
    private val onItemClick: (ConfigurationItem) -> Unit,
    private val onItemLongClick: (ConfigurationItem) -> Boolean
) : RecyclerView.Adapter<ConfigurationAdapter.ViewHolder>() {
    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_configuration, parent, false)
        return ViewHolder(view)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val item = items[position]
        when (item) {
            is ConfigurationItem.BundledEditor -> {
                holder.titleText.text = holder.itemView.context.getString(R.string.bundled_editor)
                holder.subtitleText.text =
                    holder.itemView.context.getString(R.string.bundled_editor_subtitle)
                holder.subtitleText.visibility = View.VISIBLE
            }

            is ConfigurationItem.LocalWordPress -> {
                holder.titleText.text = holder.itemView.context.getString(R.string.local_wordpress)
                holder.subtitleText.text =
                    holder.itemView.context.getString(R.string.local_wordpress_subtitle)
                holder.subtitleText.visibility = View.VISIBLE
            }

            is ConfigurationItem.ConfiguredEditor -> {
                holder.titleText.text = item.name
                holder.subtitleText.text = item.siteUrl
                holder.subtitleText.visibility = View.VISIBLE
            }
        }

        holder.itemView.setOnClickListener {
            onItemClick(item)
        }

        holder.itemView.setOnLongClickListener {
            onItemLongClick(item)
        }
    }

    override fun getItemCount() = items.size

    class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val titleText: TextView = view.findViewById(R.id.titleText)
        val subtitleText: TextView = view.findViewById(R.id.subtitleText)
    }
}