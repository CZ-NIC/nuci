#ifndef CMODEL_H
#define CMODEL_H

#include <QAbstractItemModel>
#include <QDomDocument>

class ConfigModel : public QAbstractItemModel {
public:
	ConfigModel(const QDomDocument &configData);
	virtual QModelIndex index(int row, int column, const QModelIndex &parent) const;
	virtual QModelIndex parent(const QModelIndex &index) const;
	virtual int rowCount(const QModelIndex &parent) const;
	virtual int columnCount(const QModelIndex &parent) const;
	virtual QVariant data(const QModelIndex &index, int role) const;
	virtual QVariant headerData(int section, Qt::Orientation orientation, int role) const;
private:
	class Elem;
	class ConfigFile;
	class Section;
	class Option;
	class SimpleOption;
	class ListOption;
	class Value;
	const QDomDocument configData;
	// FIXME: These things just leak. Nobody cares for now.
	QList<const ConfigFile *> configs;
};

#endif
