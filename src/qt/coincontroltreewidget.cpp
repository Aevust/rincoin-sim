// Copyright (c) 2011-2018 The Bitcoin Core developers
// Distributed under the MIT software license, see the accompanying
// file COPYING or http://www.opensource.org/licenses/mit-license.php.

#include <qt/coincontroltreewidget.h>
#include <qt/coincontroldialog.h>

CoinControlTreeWidget::CoinControlTreeWidget(QWidget *parent) :
    QTreeWidget(parent),
    m_lastClickedItem(nullptr)
{

}

void CoinControlTreeWidget::keyPressEvent(QKeyEvent *event)
{
    if (event->key() == Qt::Key_Space) // press spacebar -> select checkbox
    {
        event->ignore();
        if (this->currentItem()) {
            int COLUMN_CHECKBOX = 0;
            this->currentItem()->setCheckState(COLUMN_CHECKBOX, ((this->currentItem()->checkState(COLUMN_CHECKBOX) == Qt::Checked) ? Qt::Unchecked : Qt::Checked));
        }
    }
    else if (event->key() == Qt::Key_Escape) // press esc -> close dialog
    {
        event->ignore();
        CoinControlDialog *coinControlDialog = static_cast<CoinControlDialog*>(this->parentWidget());
        coinControlDialog->done(QDialog::Accepted);
    }
    else
    {
        this->QTreeWidget::keyPressEvent(event);
    }
}

void CoinControlTreeWidget::mousePressEvent(QMouseEvent *event)
{
    QTreeWidgetItem* clickedItem = itemAt(event->pos());
    
    // Handle shift+click for range selection
    if (event->modifiers() & Qt::ShiftModifier && clickedItem && m_lastClickedItem) {
        int COLUMN_CHECKBOX = 0;
        
        // Get the check state of the last clicked item and invert it for the target state
        // If last item was checked, we uncheck the range; if unchecked, we check the range
        Qt::CheckState lastState = m_lastClickedItem->checkState(COLUMN_CHECKBOX);
        Qt::CheckState targetState = (lastState == Qt::Checked) ? Qt::Unchecked : Qt::Checked;
        
        // Build a list of all visible items in order
        QList<QTreeWidgetItem*> allItems;
        QTreeWidgetItemIterator it(this);
        while (*it) {
            if (!(*it)->isHidden()) {
                allItems.append(*it);
            }
            ++it;
        }
        
        // Find indices of both items
        int lastIndex = allItems.indexOf(m_lastClickedItem);
        int clickedIndex = allItems.indexOf(clickedItem);
        
        if (lastIndex != -1 && clickedIndex != -1) {
            // Determine range (handle both directions)
            int startIndex = qMin(lastIndex, clickedIndex);
            int endIndex = qMax(lastIndex, clickedIndex);
            
            // Get the parent dialog to access coin control
            CoinControlDialog *coinControlDialog = static_cast<CoinControlDialog*>(this->parentWidget());
            
            // Block signals to prevent multiple updates
            blockSignals(true);
            
            // Apply the target state to all items in range and update coin control
            for (int i = startIndex; i <= endIndex; i++) {
                QTreeWidgetItem* item = allItems[i];
                if (!item->isDisabled() && item->checkState(COLUMN_CHECKBOX) != targetState) {
                    item->setCheckState(COLUMN_CHECKBOX, targetState);
                    
                    // Update coin control selection for actual coin items (not parent nodes)
                    // Check if this is a leaf node by testing if it has transaction data
                    if (item->data(COLUMN_CHECKBOX, Qt::UserRole + 1).toString().length() == 64 ||  // TxHashRole
                        item->data(COLUMN_CHECKBOX, Qt::UserRole + 4).toString().length() == 64) {  // MWEBOutRole
                        
                        // This will be handled by emitting itemChanged signals after unblocking
                    }
                }
            }
            
            // Re-enable signals
            blockSignals(false);
            
            // Emit itemChanged for all changed items to update coin control
            for (int i = startIndex; i <= endIndex; i++) {
                QTreeWidgetItem* item = allItems[i];
                if (!item->isDisabled() && item->checkState(COLUMN_CHECKBOX) == targetState) {
                    Q_EMIT itemChanged(item, COLUMN_CHECKBOX);
                }
            }
            
            // Set current item to move the visual focus/cursor to the clicked item
            setCurrentItem(clickedItem);
            
            // Update last clicked item so next shift+click uses this as the reference
            m_lastClickedItem = clickedItem;
        }
        
        event->accept();
        return;
    }
    
    // Normal click processing
    QTreeWidget::mousePressEvent(event);
    
    // Update last clicked item if we clicked on a valid item
    if (clickedItem) {
        m_lastClickedItem = clickedItem;
    }
}
